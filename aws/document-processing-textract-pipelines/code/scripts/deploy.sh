#!/bin/bash

# Document Processing Pipeline Deployment Script
# This script deploys the complete document processing pipeline using
# Amazon Textract, Step Functions, S3, Lambda, and DynamoDB

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log "Running in dry-run mode"
fi

# Function to execute commands with dry-run support
execute() {
    local cmd="$1"
    local description="${2:-}"
    
    if [[ -n "$description" ]]; then
        log "$description"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case $resource_type in
        "s3-bucket")
            aws s3api head-bucket --bucket "$resource_name" 2>/dev/null
            ;;
        "dynamodb-table")
            aws dynamodb describe-table --table-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "stepfunctions-statemachine")
            aws stepfunctions describe-state-machine --state-machine-arn "$resource_name" 2>/dev/null >/dev/null
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "$resource_name" 2>/dev/null >/dev/null
            ;;
    esac
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local caller_identity
    caller_identity=$(aws sts get-caller-identity 2>/dev/null || echo "")
    if [[ -z "$caller_identity" ]]; then
        error "Unable to verify AWS credentials"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region)
    
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using default: us-east-1"
    fi
    
    # Generate unique suffix for resources
    export BUCKET_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    export DOCUMENT_BUCKET="document-processing-$BUCKET_SUFFIX"
    export RESULTS_BUCKET="processing-results-$BUCKET_SUFFIX"
    
    log "Environment variables set:"
    log "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log "  AWS_REGION: $AWS_REGION"
    log "  DOCUMENT_BUCKET: $DOCUMENT_BUCKET"
    log "  RESULTS_BUCKET: $RESULTS_BUCKET"
    
    # Save environment variables for cleanup script
    cat > "$SCRIPT_DIR/.env" << EOF
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
AWS_REGION=$AWS_REGION
BUCKET_SUFFIX=$BUCKET_SUFFIX
DOCUMENT_BUCKET=$DOCUMENT_BUCKET
RESULTS_BUCKET=$RESULTS_BUCKET
EOF
    
    success "Environment variables configured"
}

# Create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create document bucket
    if resource_exists "s3-bucket" "$DOCUMENT_BUCKET"; then
        warning "Document bucket $DOCUMENT_BUCKET already exists, skipping creation"
    else
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            execute "aws s3api create-bucket --bucket $DOCUMENT_BUCKET --region $AWS_REGION" \
                "Creating document bucket: $DOCUMENT_BUCKET"
        else
            execute "aws s3api create-bucket --bucket $DOCUMENT_BUCKET --region $AWS_REGION \
                --create-bucket-configuration LocationConstraint=$AWS_REGION" \
                "Creating document bucket: $DOCUMENT_BUCKET"
        fi
        success "Document bucket created: $DOCUMENT_BUCKET"
    fi
    
    # Create results bucket
    if resource_exists "s3-bucket" "$RESULTS_BUCKET"; then
        warning "Results bucket $RESULTS_BUCKET already exists, skipping creation"
    else
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            execute "aws s3api create-bucket --bucket $RESULTS_BUCKET --region $AWS_REGION" \
                "Creating results bucket: $RESULTS_BUCKET"
        else
            execute "aws s3api create-bucket --bucket $RESULTS_BUCKET --region $AWS_REGION \
                --create-bucket-configuration LocationConstraint=$AWS_REGION" \
                "Creating results bucket: $RESULTS_BUCKET"
        fi
        success "Results bucket created: $RESULTS_BUCKET"
    fi
}

# Create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table..."
    
    if resource_exists "dynamodb-table" "DocumentProcessingJobs"; then
        warning "DynamoDB table DocumentProcessingJobs already exists, skipping creation"
    else
        execute "aws dynamodb create-table \
            --table-name DocumentProcessingJobs \
            --attribute-definitions AttributeName=JobId,AttributeType=S \
            --key-schema AttributeName=JobId,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region $AWS_REGION" \
            "Creating DynamoDB table: DocumentProcessingJobs"
        
        # Wait for table to be active
        if [[ "$DRY_RUN" == "false" ]]; then
            log "Waiting for DynamoDB table to become active..."
            aws dynamodb wait table-exists --table-name DocumentProcessingJobs --region "$AWS_REGION"
        fi
        
        success "DynamoDB table created: DocumentProcessingJobs"
    fi
}

# Create SNS topic
create_sns_topic() {
    log "Creating SNS topic..."
    
    local topic_arn
    topic_arn=$(aws sns create-topic --name DocumentProcessingNotifications \
        --region "$AWS_REGION" --query TopicArn --output text 2>/dev/null || echo "")
    
    if [[ -n "$topic_arn" ]]; then
        export NOTIFICATION_TOPIC_ARN="$topic_arn"
        echo "NOTIFICATION_TOPIC_ARN=$topic_arn" >> "$SCRIPT_DIR/.env"
        success "SNS topic created: $topic_arn"
    else
        error "Failed to create SNS topic"
        exit 1
    fi
}

# Create IAM role and policies
create_iam_role() {
    log "Creating IAM role and policies..."
    
    # Create trust policy
    cat > "$TEMP_DIR/step-functions-trust-policy.json" << 'EOF'
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
    
    # Create IAM role
    if resource_exists "iam-role" "DocumentProcessingStepFunctionsRole"; then
        warning "IAM role DocumentProcessingStepFunctionsRole already exists, skipping creation"
    else
        execute "aws iam create-role \
            --role-name DocumentProcessingStepFunctionsRole \
            --assume-role-policy-document file://$TEMP_DIR/step-functions-trust-policy.json" \
            "Creating IAM role: DocumentProcessingStepFunctionsRole"
        success "IAM role created: DocumentProcessingStepFunctionsRole"
    fi
    
    # Create policy document
    cat > "$TEMP_DIR/step-functions-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "textract:AnalyzeDocument",
        "textract:DetectDocumentText",
        "textract:GetDocumentAnalysis",
        "textract:GetDocumentTextDetection",
        "textract:StartDocumentAnalysis",
        "textract:StartDocumentTextDetection"
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
        "arn:aws:s3:::$DOCUMENT_BUCKET/*",
        "arn:aws:s3:::$RESULTS_BUCKET/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:GetItem"
      ],
      "Resource": "arn:aws:dynamodb:$AWS_REGION:$AWS_ACCOUNT_ID:table/DocumentProcessingJobs"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "states:StartExecution"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    # Attach policy to role
    execute "aws iam put-role-policy \
        --role-name DocumentProcessingStepFunctionsRole \
        --policy-name DocumentProcessingPolicy \
        --policy-document file://$TEMP_DIR/step-functions-policy.json" \
        "Attaching policy to IAM role"
    
    success "IAM role and policies configured"
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    # Create Lambda function code
    cat > "$TEMP_DIR/lambda-trigger.py" << 'EOF'
import json
import boto3
import uuid
import os
from urllib.parse import unquote_plus

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        # Determine if document requires advanced analysis
        requires_analysis = key.lower().endswith(('.pdf', '.tiff')) or 'form' in key.lower()
        
        # Generate unique job ID
        job_id = str(uuid.uuid4())
        
        # Prepare input for Step Functions
        input_data = {
            'bucket': bucket,
            'key': key,
            'jobId': job_id,
            'requiresAnalysis': requires_analysis
        }
        
        # Start Step Functions execution
        response = stepfunctions.start_execution(
            stateMachineArn=os.environ['STATE_MACHINE_ARN'],
            name=f'doc-processing-{job_id}',
            input=json.dumps(input_data)
        )
        
        print(f'Started processing job {job_id} for document {key}')
    
    return {'statusCode': 200}
EOF
    
    # Create deployment package
    cd "$TEMP_DIR"
    zip -q lambda-trigger.zip lambda-trigger.py
    cd - > /dev/null
    
    # Create Lambda function
    if resource_exists "lambda-function" "DocumentProcessingTrigger"; then
        warning "Lambda function DocumentProcessingTrigger already exists, updating code"
        execute "aws lambda update-function-code \
            --function-name DocumentProcessingTrigger \
            --zip-file fileb://$TEMP_DIR/lambda-trigger.zip" \
            "Updating Lambda function code"
    else
        execute "aws lambda create-function \
            --function-name DocumentProcessingTrigger \
            --runtime python3.9 \
            --role arn:aws:iam::$AWS_ACCOUNT_ID:role/DocumentProcessingStepFunctionsRole \
            --handler lambda-trigger.lambda_handler \
            --zip-file fileb://$TEMP_DIR/lambda-trigger.zip \
            --timeout 60 \
            --memory-size 256" \
            "Creating Lambda function: DocumentProcessingTrigger"
    fi
    
    success "Lambda function created: DocumentProcessingTrigger"
}

# Create Step Functions state machine
create_step_functions() {
    log "Creating Step Functions state machine..."
    
    # Create state machine definition
    cat > "$TEMP_DIR/document-processing-workflow.json" << EOF
{
  "Comment": "Document processing pipeline with Textract",
  "StartAt": "ProcessDocument",
  "States": {
    "ProcessDocument": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.requiresAnalysis",
          "BooleanEquals": true,
          "Next": "AnalyzeDocument"
        }
      ],
      "Default": "DetectText"
    },
    "AnalyzeDocument": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:textract:analyzeDocument",
      "Parameters": {
        "Document": {
          "S3Object": {
            "Bucket.$": "$.bucket",
            "Name.$": "$.key"
          }
        },
        "FeatureTypes": ["TABLES", "FORMS", "SIGNATURES"]
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
      "Next": "StoreResults"
    },
    "DetectText": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:textract:detectDocumentText",
      "Parameters": {
        "Document": {
          "S3Object": {
            "Bucket.$": "$.bucket",
            "Name.$": "$.key"
          }
        }
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
      "Next": "StoreResults"
    },
    "StoreResults": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:putObject",
      "Parameters": {
        "Bucket": "$RESULTS_BUCKET",
        "Key.$": "States.Format('{}/results.json', $.jobId)",
        "Body.$": "$"
      },
      "Next": "UpdateJobStatus"
    },
    "UpdateJobStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:dynamodb:putItem",
      "Parameters": {
        "TableName": "DocumentProcessingJobs",
        "Item": {
          "JobId": {
            "S.$": "$.jobId"
          },
          "Status": {
            "S": "COMPLETED"
          },
          "ProcessedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          "ResultsLocation": {
            "S.$": "States.Format('s3://$RESULTS_BUCKET/{}/results.json', $.jobId)"
          }
        }
      },
      "Next": "SendNotification"
    },
    "SendNotification": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:sns:publish",
      "Parameters": {
        "TopicArn": "$NOTIFICATION_TOPIC_ARN",
        "Message.$": "States.Format('Document processing completed for job {}', $.jobId)",
        "Subject": "Document Processing Complete"
      },
      "End": true
    },
    "ProcessingFailed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:dynamodb:putItem",
      "Parameters": {
        "TableName": "DocumentProcessingJobs",
        "Item": {
          "JobId": {
            "S.$": "$.jobId"
          },
          "Status": {
            "S": "FAILED"
          },
          "FailedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          "Error": {
            "S.$": "$.Error"
          }
        }
      },
      "Next": "NotifyFailure"
    },
    "NotifyFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:sns:publish",
      "Parameters": {
        "TopicArn": "$NOTIFICATION_TOPIC_ARN",
        "Message.$": "States.Format('Document processing failed for job {}', $.jobId)",
        "Subject": "Document Processing Failed"
      },
      "End": true
    }
  }
}
EOF
    
    # Create state machine
    local state_machine_arn
    state_machine_arn=$(aws stepfunctions create-state-machine \
        --name DocumentProcessingPipeline \
        --definition file://"$TEMP_DIR/document-processing-workflow.json" \
        --role-arn "arn:aws:iam::$AWS_ACCOUNT_ID:role/DocumentProcessingStepFunctionsRole" \
        --query stateMachineArn --output text 2>/dev/null || echo "")
    
    if [[ -n "$state_machine_arn" ]]; then
        export STATE_MACHINE_ARN="$state_machine_arn"
        echo "STATE_MACHINE_ARN=$state_machine_arn" >> "$SCRIPT_DIR/.env"
        success "Step Functions state machine created: $state_machine_arn"
    else
        error "Failed to create Step Functions state machine"
        exit 1
    fi
}

# Update Lambda function with state machine ARN
update_lambda_environment() {
    log "Updating Lambda function environment variables..."
    
    execute "aws lambda update-function-configuration \
        --function-name DocumentProcessingTrigger \
        --environment Variables='{\"STATE_MACHINE_ARN\":\"$STATE_MACHINE_ARN\"}'" \
        "Setting STATE_MACHINE_ARN environment variable"
    
    success "Lambda function environment updated"
}

# Configure S3 event notifications
configure_s3_events() {
    log "Configuring S3 event notifications..."
    
    # Add Lambda permission for S3
    aws lambda add-permission \
        --function-name DocumentProcessingTrigger \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --source-arn "arn:aws:s3:::$DOCUMENT_BUCKET" \
        --statement-id s3-trigger-permission \
        2>/dev/null || warning "Permission may already exist"
    
    # Create S3 notification configuration
    local lambda_function_arn="arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:DocumentProcessingTrigger"
    
    cat > "$TEMP_DIR/s3-notification.json" << EOF
{
  "LambdaConfigurations": [
    {
      "Id": "DocumentProcessingTrigger",
      "LambdaFunctionArn": "$lambda_function_arn",
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
    
    execute "aws s3api put-bucket-notification-configuration \
        --bucket $DOCUMENT_BUCKET \
        --notification-configuration file://$TEMP_DIR/s3-notification.json" \
        "Configuring S3 event notifications"
    
    success "S3 event notifications configured"
}

# Test deployment
test_deployment() {
    log "Testing deployment..."
    
    # Create a simple test document
    echo "This is a test document for the processing pipeline." > "$TEMP_DIR/test-document.txt"
    
    # Upload test document
    execute "aws s3 cp $TEMP_DIR/test-document.txt s3://$DOCUMENT_BUCKET/test-document.pdf" \
        "Uploading test document"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait a moment for processing
        sleep 5
        
        # Check if execution started
        local executions
        executions=$(aws stepfunctions list-executions \
            --state-machine-arn "$STATE_MACHINE_ARN" \
            --max-items 1 \
            --query 'executions[0].name' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$executions" && "$executions" != "None" ]]; then
            success "Test execution started successfully"
        else
            warning "No executions found yet - this may be normal if processing is still starting"
        fi
    fi
    
    success "Deployment test completed"
}

# Main deployment function
main() {
    log "Starting document processing pipeline deployment..."
    
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_dynamodb_table
    create_sns_topic
    create_iam_role
    create_lambda_function
    create_step_functions
    update_lambda_environment
    configure_s3_events
    test_deployment
    
    echo
    success "Document processing pipeline deployed successfully!"
    echo
    log "Deployment Summary:"
    log "  Document Bucket: $DOCUMENT_BUCKET"
    log "  Results Bucket: $RESULTS_BUCKET"
    log "  DynamoDB Table: DocumentProcessingJobs"
    log "  Lambda Function: DocumentProcessingTrigger"
    log "  Step Functions: DocumentProcessingPipeline"
    log "  SNS Topic: $NOTIFICATION_TOPIC_ARN"
    echo
    log "To test the pipeline, upload a PDF file to the document bucket:"
    log "  aws s3 cp your-document.pdf s3://$DOCUMENT_BUCKET/"
    echo
    log "To monitor executions:"
    log "  aws stepfunctions list-executions --state-machine-arn $STATE_MACHINE_ARN"
    echo
    log "Environment variables saved to: $SCRIPT_DIR/.env"
    log "Use ./destroy.sh to clean up all resources"
}

# Run main function
main "$@"