#!/bin/bash
set -e

# AWS Textract and Step Functions Document Processing Pipeline Deployment Script
# This script creates a complete serverless document processing pipeline using
# Amazon Textract for intelligent document extraction and Step Functions for orchestration

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$1" == "--dry-run" ]] || [[ "$DRY_RUN" == "true" ]]; then
    DRY_RUN=true
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would execute: $cmd"
        if [[ -n "$description" ]]; then
            log "DRY-RUN: $description"
        fi
        return 0
    else
        log "Executing: $description"
        eval "$cmd"
        return $?
    fi
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Starting cleanup of partially created resources..."
    
    if [[ -n "$PROJECT_NAME" ]]; then
        # Remove Lambda functions if they exist
        for func in "document-processor" "results-processor" "s3-trigger"; do
            if aws lambda get-function --function-name "${PROJECT_NAME}-${func}" &>/dev/null; then
                warning "Cleaning up Lambda function: ${PROJECT_NAME}-${func}"
                aws lambda delete-function --function-name "${PROJECT_NAME}-${func}" || true
            fi
        done
        
        # Remove Step Functions state machine if it exists
        if [[ -n "$STATE_MACHINE_ARN" ]]; then
            warning "Cleaning up Step Functions state machine"
            aws stepfunctions delete-state-machine --state-machine-arn "$STATE_MACHINE_ARN" || true
        fi
        
        # Remove S3 buckets if they exist
        for bucket in "$INPUT_BUCKET" "$OUTPUT_BUCKET" "$ARCHIVE_BUCKET"; do
            if [[ -n "$bucket" ]] && aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
                warning "Cleaning up S3 bucket: $bucket"
                aws s3 rm "s3://$bucket" --recursive || true
                aws s3 rb "s3://$bucket" || true
            fi
        done
        
        # Remove IAM roles if they exist
        for role in "${PROJECT_NAME}-lambda-role" "${PROJECT_NAME}-stepfunctions-role"; do
            if aws iam get-role --role-name "$role" &>/dev/null; then
                warning "Cleaning up IAM role: $role"
                # Detach policies first
                aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text | \
                    xargs -I {} aws iam detach-role-policy --role-name "$role" --policy-arn {} || true
                aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text | \
                    xargs -I {} aws iam delete-role-policy --role-name "$role" --policy-name {} || true
                aws iam delete-role --role-name "$role" || true
            fi
        done
    fi
    
    # Remove temporary files
    rm -f *.json *.py *.zip *.txt
    
    error "Cleanup completed. Please check for any remaining resources manually."
    exit 1
}

# Set error trap
trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &>/dev/null; then
        error "AWS CLI is not configured or authentication failed"
        error "Please run 'aws configure' or set up your credentials"
        exit 1
    fi
    
    # Check for required tools
    local required_tools=("jq" "zip" "unzip")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check AWS permissions
    log "Verifying AWS permissions..."
    if ! aws iam get-user &>/dev/null && ! aws sts get-caller-identity &>/dev/null; then
        error "Unable to verify AWS credentials"
        exit 1
    fi
    
    # Check required AWS services availability in region
    local region=$(aws configure get region)
    if [[ -z "$region" ]]; then
        error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    # Verify service availability
    local services=("lambda" "stepfunctions" "textract" "s3" "iam")
    for service in "${services[@]}"; do
        if ! aws "$service" help &>/dev/null; then
            error "AWS $service is not available or CLI is outdated"
            exit 1
        fi
    done
    
    success "Prerequisites check completed"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not configured"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error "Unable to get AWS account ID"
        exit 1
    fi
    
    # Generate unique project name
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s)")
    
    export PROJECT_NAME="textract-pipeline-${random_suffix}"
    export INPUT_BUCKET="${PROJECT_NAME}-input"
    export OUTPUT_BUCKET="${PROJECT_NAME}-output"
    export ARCHIVE_BUCKET="${PROJECT_NAME}-archive"
    
    log "Project name: $PROJECT_NAME"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    
    success "Environment variables initialized"
}

# Create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create buckets with error handling
    for bucket in "$INPUT_BUCKET" "$OUTPUT_BUCKET" "$ARCHIVE_BUCKET"; do
        if aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            warning "Bucket $bucket already exists"
        else
            execute_command "aws s3 mb s3://$bucket --region $AWS_REGION" "Creating bucket: $bucket"
            
            # Enable versioning for input bucket
            if [[ "$bucket" == "$INPUT_BUCKET" ]]; then
                execute_command "aws s3api put-bucket-versioning --bucket $bucket --versioning-configuration Status=Enabled" \
                    "Enabling versioning for input bucket"
            fi
            
            # Apply lifecycle rules for cost optimization
            if [[ "$bucket" == "$ARCHIVE_BUCKET" ]]; then
                cat > lifecycle-config.json << EOF
{
  "Rules": [
    {
      "ID": "ArchiveRule",
      "Status": "Enabled",
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
                execute_command "aws s3api put-bucket-lifecycle-configuration --bucket $bucket --lifecycle-configuration file://lifecycle-config.json" \
                    "Applying lifecycle policy to archive bucket"
            fi
        fi
    done
    
    success "S3 buckets created successfully"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create Step Functions trust policy
    cat > step-functions-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "states.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create Step Functions role
    if aws iam get-role --role-name "${PROJECT_NAME}-stepfunctions-role" &>/dev/null; then
        warning "Step Functions role already exists"
    else
        execute_command "aws iam create-role --role-name ${PROJECT_NAME}-stepfunctions-role --assume-role-policy-document file://step-functions-trust-policy.json" \
            "Creating Step Functions IAM role"
    fi
    
    # Create Step Functions execution policy
    cat > step-functions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Resource": [
        "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "textract:StartDocumentAnalysis",
        "textract:StartDocumentTextDetection",
        "textract:GetDocumentAnalysis",
        "textract:GetDocumentTextDetection"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::${INPUT_BUCKET}/*",
        "arn:aws:s3:::${OUTPUT_BUCKET}/*",
        "arn:aws:s3:::${ARCHIVE_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:*"
    }
  ]
}
EOF
    
    execute_command "aws iam put-role-policy --role-name ${PROJECT_NAME}-stepfunctions-role --policy-name StepFunctionsExecutionPolicy --policy-document file://step-functions-policy.json" \
        "Attaching policy to Step Functions role"
    
    export STEPFUNCTIONS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-stepfunctions-role"
    
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
    
    # Create Lambda role
    if aws iam get-role --role-name "${PROJECT_NAME}-lambda-role" &>/dev/null; then
        warning "Lambda role already exists"
    else
        execute_command "aws iam create-role --role-name ${PROJECT_NAME}-lambda-role --assume-role-policy-document file://lambda-trust-policy.json" \
            "Creating Lambda IAM role"
    fi
    
    # Wait for role propagation
    sleep 10
    
    # Attach managed policies to Lambda role
    local lambda_policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/AmazonTextractFullAccess"
        "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
    )
    
    for policy in "${lambda_policies[@]}"; do
        execute_command "aws iam attach-role-policy --role-name ${PROJECT_NAME}-lambda-role --policy-arn $policy" \
            "Attaching policy: $policy"
    done
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role"
    
    success "IAM roles created successfully"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create document processor function
    cat > document-processor.py << 'EOF'
import json
import boto3
import logging
from urllib.parse import unquote_plus

logger = logging.getLogger()
logger.setLevel(logging.INFO)

textract = boto3.client('textract')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Extract S3 information from event
        bucket = event['bucket']
        key = unquote_plus(event['key'])
        
        logger.info(f"Processing document: s3://{bucket}/{key}")
        
        # Determine document type and processing method
        file_extension = key.lower().split('.')[-1]
        
        # Configure Textract parameters based on document type
        if file_extension in ['pdf', 'png', 'jpg', 'jpeg', 'tiff']:
            # Start document analysis for complex documents
            response = textract.start_document_analysis(
                DocumentLocation={
                    'S3Object': {
                        'Bucket': bucket,
                        'Name': key
                    }
                },
                FeatureTypes=['TABLES', 'FORMS', 'SIGNATURES']
            )
            
            job_id = response['JobId']
            
            return {
                'statusCode': 200,
                'jobId': job_id,
                'jobType': 'ANALYSIS',
                'bucket': bucket,
                'key': key,
                'documentType': file_extension
            }
        else:
            raise ValueError(f"Unsupported file type: {file_extension}")
            
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
EOF
    
    execute_command "zip -j document-processor.zip document-processor.py" "Packaging document processor"
    
    if aws lambda get-function --function-name "${PROJECT_NAME}-document-processor" &>/dev/null; then
        warning "Document processor function already exists"
    else
        execute_command "aws lambda create-function --function-name ${PROJECT_NAME}-document-processor --runtime python3.11 --role ${LAMBDA_ROLE_ARN} --handler document-processor.lambda_handler --zip-file fileb://document-processor.zip --timeout 60 --memory-size 256 --description 'Initiates Textract document processing'" \
            "Creating document processor Lambda function"
    fi
    
    # Create results processor function
    cat > results-processor.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

textract = boto3.client('textract')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        job_id = event['jobId']
        job_type = event['jobType']
        bucket = event['bucket']
        key = event['key']
        
        logger.info(f"Processing results for job: {job_id}")
        
        # Get Textract results based on job type
        if job_type == 'ANALYSIS':
            response = textract.get_document_analysis(JobId=job_id)
        else:
            response = textract.get_document_text_detection(JobId=job_id)
        
        # Check job status
        job_status = response['JobStatus']
        
        if job_status == 'SUCCEEDED':
            # Process and structure the results
            processed_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'sourceDocument': f"s3://{bucket}/{key}",
                'jobId': job_id,
                'jobType': job_type,
                'documentMetadata': response.get('DocumentMetadata', {}),
                'extractedData': {
                    'text': [],
                    'tables': [],
                    'forms': []
                }
            }
            
            # Parse blocks and extract meaningful data
            blocks = response.get('Blocks', [])
            
            for block in blocks:
                if block['BlockType'] == 'LINE':
                    processed_data['extractedData']['text'].append({
                        'text': block.get('Text', ''),
                        'confidence': block.get('Confidence', 0),
                        'geometry': block.get('Geometry', {})
                    })
                elif block['BlockType'] == 'TABLE':
                    # Process table data with enhanced metadata
                    table_data = {
                        'id': block.get('Id', ''),
                        'confidence': block.get('Confidence', 0),
                        'geometry': block.get('Geometry', {}),
                        'rowCount': block.get('RowCount', 0),
                        'columnCount': block.get('ColumnCount', 0)
                    }
                    processed_data['extractedData']['tables'].append(table_data)
                elif block['BlockType'] == 'KEY_VALUE_SET':
                    # Process form data
                    if block.get('EntityTypes') and 'KEY' in block['EntityTypes']:
                        form_data = {
                            'id': block.get('Id', ''),
                            'confidence': block.get('Confidence', 0),
                            'geometry': block.get('Geometry', {}),
                            'text': block.get('Text', '')
                        }
                        processed_data['extractedData']['forms'].append(form_data)
            
            # Save processed results to S3 output bucket
            output_key = f"processed/{key.replace('.', '_')}_results.json"
            
            s3.put_object(
                Bucket=event.get('outputBucket', bucket),
                Key=output_key,
                Body=json.dumps(processed_data, indent=2),
                ContentType='application/json',
                Metadata={
                    'source-bucket': bucket,
                    'source-key': key,
                    'processing-timestamp': datetime.utcnow().isoformat()
                }
            )
            
            # Archive original document with date-based organization
            if 'archiveBucket' in event:
                archive_key = f"archive/{datetime.utcnow().strftime('%Y/%m/%d')}/{key}"
                s3.copy_object(
                    CopySource={'Bucket': bucket, 'Key': key},
                    Bucket=event['archiveBucket'],
                    Key=archive_key
                )
            
            return {
                'statusCode': 200,
                'status': 'COMPLETED',
                'outputLocation': f"s3://{event.get('outputBucket', bucket)}/{output_key}",
                'extractedItems': {
                    'textLines': len(processed_data['extractedData']['text']),
                    'tables': len(processed_data['extractedData']['tables']),
                    'forms': len(processed_data['extractedData']['forms'])
                }
            }
            
        elif job_status == 'FAILED':
            logger.error(f"Textract job failed: {job_id}")
            return {
                'statusCode': 500,
                'status': 'FAILED',
                'error': 'Textract job failed'
            }
        else:
            # Job still in progress
            return {
                'statusCode': 202,
                'status': 'IN_PROGRESS',
                'message': f"Job status: {job_status}"
            }
            
    except Exception as e:
        logger.error(f"Error processing results: {str(e)}")
        return {
            'statusCode': 500,
            'status': 'ERROR',
            'error': str(e)
        }
EOF
    
    execute_command "zip -j results-processor.zip results-processor.py" "Packaging results processor"
    
    if aws lambda get-function --function-name "${PROJECT_NAME}-results-processor" &>/dev/null; then
        warning "Results processor function already exists"
    else
        execute_command "aws lambda create-function --function-name ${PROJECT_NAME}-results-processor --runtime python3.11 --role ${LAMBDA_ROLE_ARN} --handler results-processor.lambda_handler --zip-file fileb://results-processor.zip --timeout 300 --memory-size 512 --description 'Processes and formats Textract extraction results'" \
            "Creating results processor Lambda function"
    fi
    
    # Create S3 trigger function
    cat > s3-trigger.py << 'EOF'
import json
import boto3
import logging
import os
from urllib.parse import unquote_plus

logger = logging.getLogger()
logger.setLevel(logging.INFO)

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    try:
        state_machine_arn = os.environ['STATE_MACHINE_ARN']
        
        # Process S3 event records
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"New document uploaded: s3://{bucket}/{key}")
            
            # Start Step Functions execution
            execution_input = {
                'bucket': bucket,
                'key': key,
                'eventTime': record['eventTime']
            }
            
            execution_name = f"doc-processing-{key.replace('/', '-').replace('.', '-')}-{context.aws_request_id[:8]}"
            
            response = stepfunctions.start_execution(
                stateMachineArn=state_machine_arn,
                name=execution_name,
                input=json.dumps(execution_input)
            )
            
            logger.info(f"Started execution: {response['executionArn']}")
            
        return {
            'statusCode': 200,
            'message': f"Processed {len(event['Records'])} document(s)"
        }
        
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
EOF
    
    success "Lambda functions created successfully"
}

# Create Step Functions state machine
create_state_machine() {
    log "Creating Step Functions state machine..."
    
    # Create state machine definition
    cat > state-machine-definition.json << EOF
{
  "Comment": "Document Processing Pipeline with Amazon Textract",
  "StartAt": "ProcessDocument",
  "States": {
    "ProcessDocument": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-document-processor",
      "Parameters": {
        "bucket.$": "$.bucket",
        "key.$": "$.key"
      },
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 5,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ProcessingFailed"
        }
      ],
      "Next": "WaitForTextractCompletion"
    },
    "WaitForTextractCompletion": {
      "Type": "Wait",
      "Seconds": 30,
      "Next": "CheckTextractStatus"
    },
    "CheckTextractStatus": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-results-processor",
      "Parameters": {
        "jobId.$": "$.jobId",
        "jobType.$": "$.jobType",
        "bucket.$": "$.bucket",
        "key.$": "$.key",
        "outputBucket": "${OUTPUT_BUCKET}",
        "archiveBucket": "${ARCHIVE_BUCKET}"
      },
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 10,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Next": "EvaluateStatus"
    },
    "EvaluateStatus": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.status",
          "StringEquals": "COMPLETED",
          "Next": "ProcessingCompleted"
        },
        {
          "Variable": "$.status",
          "StringEquals": "IN_PROGRESS",
          "Next": "WaitForTextractCompletion"
        },
        {
          "Variable": "$.status",
          "StringEquals": "FAILED",
          "Next": "ProcessingFailed"
        }
      ],
      "Default": "ProcessingFailed"
    },
    "ProcessingCompleted": {
      "Type": "Succeed",
      "Result": {
        "message": "Document processing completed successfully"
      }
    },
    "ProcessingFailed": {
      "Type": "Fail",
      "Cause": "Document processing failed"
    }
  }
}
EOF
    
    # Wait for IAM role propagation
    sleep 15
    
    # Create state machine
    if aws stepfunctions describe-state-machine --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${PROJECT_NAME}-document-pipeline" &>/dev/null; then
        warning "State machine already exists"
        export STATE_MACHINE_ARN="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${PROJECT_NAME}-document-pipeline"
    else
        execute_command "aws stepfunctions create-state-machine --name ${PROJECT_NAME}-document-pipeline --definition file://state-machine-definition.json --role-arn ${STEPFUNCTIONS_ROLE_ARN} --type STANDARD" \
            "Creating Step Functions state machine"
        
        export STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='${PROJECT_NAME}-document-pipeline'].stateMachineArn" --output text)
    fi
    
    success "Step Functions state machine created successfully"
}

# Configure S3 event trigger
configure_s3_trigger() {
    log "Configuring S3 event trigger..."
    
    # Package and deploy S3 trigger Lambda
    execute_command "zip -j s3-trigger.zip s3-trigger.py" "Packaging S3 trigger function"
    
    if aws lambda get-function --function-name "${PROJECT_NAME}-s3-trigger" &>/dev/null; then
        warning "S3 trigger function already exists"
    else
        execute_command "aws lambda create-function --function-name ${PROJECT_NAME}-s3-trigger --runtime python3.11 --role ${LAMBDA_ROLE_ARN} --handler s3-trigger.lambda_handler --zip-file fileb://s3-trigger.zip --timeout 60 --memory-size 256 --environment Variables='{\"STATE_MACHINE_ARN\":\"${STATE_MACHINE_ARN}\"}' --description 'Triggers document processing pipeline from S3 events'" \
            "Creating S3 trigger Lambda function"
    fi
    
    # Add S3 invoke permission to Lambda
    execute_command "aws lambda add-permission --function-name ${PROJECT_NAME}-s3-trigger --principal s3.amazonaws.com --action lambda:InvokeFunction --statement-id s3-trigger-permission --source-arn arn:aws:s3:::${INPUT_BUCKET}" \
        "Adding S3 invoke permission to Lambda"
    
    # Configure S3 bucket notification
    cat > notification-config.json << EOF
{
  "LambdaConfigurations": [
    {
      "Id": "DocumentUploadTrigger",
      "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-s3-trigger",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "suffix",
              "Value": ".pdf"
            }
          ]
        }
      }
    }
  ]
}
EOF
    
    execute_command "aws s3api put-bucket-notification-configuration --bucket ${INPUT_BUCKET} --notification-configuration file://notification-config.json" \
        "Configuring S3 bucket notification"
    
    success "S3 event trigger configured successfully"
}

# Configure CloudWatch monitoring
configure_monitoring() {
    log "Configuring CloudWatch monitoring..."
    
    # Create log groups
    local log_groups=(
        "/aws/lambda/${PROJECT_NAME}-document-processor"
        "/aws/lambda/${PROJECT_NAME}-results-processor"
        "/aws/lambda/${PROJECT_NAME}-s3-trigger"
        "/aws/stepfunctions/${PROJECT_NAME}-document-pipeline"
    )
    
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text | grep -q "$log_group"; then
            warning "Log group already exists: $log_group"
        else
            execute_command "aws logs create-log-group --log-group-name $log_group --retention-in-days 14" \
                "Creating log group: $log_group"
        fi
    done
    
    # Create CloudWatch dashboard
    cat > dashboard-definition.json << EOF
{
  "widgets": [
    {
      "type": "metric",
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", "FunctionName", "${PROJECT_NAME}-document-processor"],
          [".", "Duration", ".", "."],
          [".", "Errors", ".", "."],
          [".", "Throttles", ".", "."]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Document Processor Lambda Metrics",
        "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["AWS/States", "ExecutionsStarted", "StateMachineArn", "${STATE_MACHINE_ARN}"],
          [".", "ExecutionsSucceeded", ".", "."],
          [".", "ExecutionsFailed", ".", "."],
          [".", "ExecutionTime", ".", "."]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Step Functions Pipeline Metrics",
        "view": "timeSeries"
      }
    }
  ]
}
EOF
    
    execute_command "aws cloudwatch put-dashboard --dashboard-name ${PROJECT_NAME}-pipeline-monitoring --dashboard-body file://dashboard-definition.json" \
        "Creating CloudWatch dashboard"
    
    success "CloudWatch monitoring configured successfully"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
  "projectName": "${PROJECT_NAME}",
  "region": "${AWS_REGION}",
  "accountId": "${AWS_ACCOUNT_ID}",
  "buckets": {
    "input": "${INPUT_BUCKET}",
    "output": "${OUTPUT_BUCKET}",
    "archive": "${ARCHIVE_BUCKET}"
  },
  "lambdaFunctions": [
    "${PROJECT_NAME}-document-processor",
    "${PROJECT_NAME}-results-processor",
    "${PROJECT_NAME}-s3-trigger"
  ],
  "stepFunctions": {
    "stateMachineArn": "${STATE_MACHINE_ARN}",
    "name": "${PROJECT_NAME}-document-pipeline"
  },
  "iamRoles": [
    "${PROJECT_NAME}-lambda-role",
    "${PROJECT_NAME}-stepfunctions-role"
  ],
  "cloudWatchDashboard": "${PROJECT_NAME}-pipeline-monitoring",
  "deploymentTimestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    success "Deployment information saved to deployment-info.json"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    local validation_errors=0
    
    # Check S3 buckets
    for bucket in "$INPUT_BUCKET" "$OUTPUT_BUCKET" "$ARCHIVE_BUCKET"; do
        if ! aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            error "S3 bucket validation failed: $bucket"
            ((validation_errors++))
        else
            success "S3 bucket validated: $bucket"
        fi
    done
    
    # Check Lambda functions
    local functions=("document-processor" "results-processor" "s3-trigger")
    for func in "${functions[@]}"; do
        if ! aws lambda get-function --function-name "${PROJECT_NAME}-${func}" &>/dev/null; then
            error "Lambda function validation failed: ${PROJECT_NAME}-${func}"
            ((validation_errors++))
        else
            success "Lambda function validated: ${PROJECT_NAME}-${func}"
        fi
    done
    
    # Check Step Functions state machine
    if ! aws stepfunctions describe-state-machine --state-machine-arn "$STATE_MACHINE_ARN" &>/dev/null; then
        error "Step Functions state machine validation failed"
        ((validation_errors++))
    else
        success "Step Functions state machine validated"
    fi
    
    # Check IAM roles
    for role in "${PROJECT_NAME}-lambda-role" "${PROJECT_NAME}-stepfunctions-role"; do
        if ! aws iam get-role --role-name "$role" &>/dev/null; then
            error "IAM role validation failed: $role"
            ((validation_errors++))
        else
            success "IAM role validated: $role"
        fi
    done
    
    if [[ $validation_errors -eq 0 ]]; then
        success "All resources validated successfully"
        return 0
    else
        error "Validation failed with $validation_errors errors"
        return 1
    fi
}

# Main deployment function
main() {
    log "Starting AWS Textract and Step Functions Document Processing Pipeline deployment..."
    
    # Run deployment steps
    check_prerequisites
    initialize_environment
    create_s3_buckets
    create_iam_roles
    create_lambda_functions
    create_state_machine
    configure_s3_trigger
    configure_monitoring
    save_deployment_info
    
    # Validate deployment
    if validate_deployment; then
        # Clean up temporary files
        rm -f *.json *.py *.zip
        
        success "Deployment completed successfully!"
        echo ""
        echo "========================================="
        echo "DEPLOYMENT SUMMARY"
        echo "========================================="
        echo "Project Name: $PROJECT_NAME"
        echo "Region: $AWS_REGION"
        echo "Input Bucket: s3://$INPUT_BUCKET"
        echo "Output Bucket: s3://$OUTPUT_BUCKET"
        echo "Archive Bucket: s3://$ARCHIVE_BUCKET"
        echo "State Machine: $STATE_MACHINE_ARN"
        echo "CloudWatch Dashboard: $PROJECT_NAME-pipeline-monitoring"
        echo ""
        echo "To test the pipeline:"
        echo "1. Upload a PDF document to: s3://$INPUT_BUCKET"
        echo "2. Monitor execution in Step Functions console"
        echo "3. Check processed results in: s3://$OUTPUT_BUCKET/processed/"
        echo ""
        echo "For cleanup, run: ./destroy.sh"
        echo "========================================="
    else
        error "Deployment validation failed"
        exit 1
    fi
}

# Run main function
main "$@"