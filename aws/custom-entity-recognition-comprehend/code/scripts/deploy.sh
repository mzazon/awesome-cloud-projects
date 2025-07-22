#!/bin/bash

# Deploy script for Custom Entity Recognition and Classification with Comprehend
# This script deploys the complete infrastructure for custom NLP models

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Logging function
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$TIMESTAMP] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic check)
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "AWS Account ID: $ACCOUNT_ID"
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log "Warning: jq not found. Some features may be limited."
    fi
    
    log "✅ Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export PROJECT_NAME="comprehend-custom-${RANDOM_SUFFIX}"
    export BUCKET_NAME="comprehend-models-${RANDOM_SUFFIX}"
    export ROLE_NAME="ComprehendCustomRole-${RANDOM_SUFFIX}"
    export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
    
    log "Project Name: $PROJECT_NAME"
    log "S3 Bucket: $BUCKET_NAME"
    log "IAM Role: $ROLE_NAME"
    log "Region: $AWS_REGION"
    
    # Save environment variables for destroy script
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_NAME=$PROJECT_NAME
BUCKET_NAME=$BUCKET_NAME
ROLE_NAME=$ROLE_NAME
ROLE_ARN=$ROLE_ARN
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
EOF
    
    log "✅ Environment setup completed"
}

# Create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for training data and models..."
    
    if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
        log "S3 bucket $BUCKET_NAME already exists"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://${BUCKET_NAME}"
        else
            aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
        fi
        log "✅ Created S3 bucket: $BUCKET_NAME"
    fi
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    log "✅ Enabled S3 bucket versioning"
}

# Create IAM role
create_iam_role() {
    log "Creating IAM role for Comprehend and services..."
    
    # Check if role already exists
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log "IAM role $ROLE_NAME already exists"
        return 0
    fi
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/trust-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "comprehend.amazonaws.com",
          "lambda.amazonaws.com",
          "states.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "file://${SCRIPT_DIR}/trust-policy.json"
    
    # Attach required policies
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/ComprehendFullAccess
    
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
    
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess
    
    # Wait for role to be available
    log "Waiting for IAM role to be ready..."
    sleep 10
    
    log "✅ Created IAM role: $ROLE_NAME"
}

# Create sample training data
create_training_data() {
    log "Creating sample training data..."
    
    mkdir -p "${SCRIPT_DIR}/training-data"
    
    # Create entity training data
    cat > "${SCRIPT_DIR}/training-data/entities.csv" << 'EOF'
Text,File,Line,BeginOffset,EndOffset,Type
"The S&P 500 index rose 2.3% yesterday.",entities_sample.txt,0,4,11,STOCK_INDEX
"Apple Inc. (AAPL) reported strong quarterly earnings.",entities_sample.txt,1,13,17,STOCK_SYMBOL
"The Federal Reserve raised interest rates by 0.25%.",entities_sample.txt,2,4,17,CENTRAL_BANK
"Goldman Sachs upgraded Microsoft to a buy rating.",entities_sample.txt,3,0,13,INVESTMENT_BANK
"Bitcoin hit a new high of $65,000 per coin.",entities_sample.txt,4,0,7,CRYPTOCURRENCY
"The NASDAQ composite closed up 150 points.",entities_sample.txt,5,4,10,STOCK_INDEX
"JPMorgan Chase announced a new credit facility.",entities_sample.txt,6,0,14,FINANCIAL_INSTITUTION
"Tesla (TSLA) stock volatility increased significantly.",entities_sample.txt,7,7,11,STOCK_SYMBOL
EOF
    
    # Create corresponding text file
    cat > "${SCRIPT_DIR}/training-data/entities_sample.txt" << 'EOF'
The S&P 500 index rose 2.3% yesterday.
Apple Inc. (AAPL) reported strong quarterly earnings.
The Federal Reserve raised interest rates by 0.25%.
Goldman Sachs upgraded Microsoft to a buy rating.
Bitcoin hit a new high of $65,000 per coin.
The NASDAQ composite closed up 150 points.
JPMorgan Chase announced a new credit facility.
Tesla (TSLA) stock volatility increased significantly.
EOF
    
    # Create classification training data
    cat > "${SCRIPT_DIR}/training-data/classification.csv" << 'EOF'
Text,Label
"Quarterly earnings report shows strong revenue growth and improved margins across all business segments.",EARNINGS_REPORT
"The Federal Reserve announced a 0.25% interest rate increase following their latest policy meeting.",MONETARY_POLICY
"New regulatory guidelines require enhanced disclosure for cryptocurrency trading platforms.",REGULATORY_NEWS
"Company announces acquisition of fintech startup for $500 million in cash and stock.",MERGER_ACQUISITION
"Market volatility increased following geopolitical tensions and inflation concerns.",MARKET_ANALYSIS
"Annual shareholder meeting scheduled for next month with executive compensation on agenda.",CORPORATE_GOVERNANCE
"Credit rating agency downgrades bank following loan loss provisions.",CREDIT_RATING
"Technology patent approval strengthens company's intellectual property portfolio.",INTELLECTUAL_PROPERTY
"Environmental impact assessment reveals need for sustainable business practices.",ESG_REPORT
"Insider trading investigation launched by securities regulators.",COMPLIANCE_ISSUE
EOF
    
    # Upload training data to S3
    aws s3 cp "${SCRIPT_DIR}/training-data/" "s3://${BUCKET_NAME}/training-data/" --recursive
    
    log "✅ Created and uploaded training data"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create data preprocessor function
    cat > "${SCRIPT_DIR}/data_preprocessor.py" << 'EOF'
import json
import boto3
import csv
from io import StringIO
import re

s3 = boto3.client('s3')

def lambda_handler(event, context):
    bucket = event['bucket']
    entity_key = event['entity_training_data']
    classification_key = event['classification_training_data']
    
    try:
        # Process entity training data
        entity_result = process_entity_data(bucket, entity_key)
        
        # Process classification training data
        classification_result = process_classification_data(bucket, classification_key)
        
        return {
            'statusCode': 200,
            'entity_training_ready': entity_result,
            'classification_training_ready': classification_result,
            'bucket': bucket
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e)
        }

def process_entity_data(bucket, key):
    # Download and validate entity training data
    response = s3.get_object(Bucket=bucket, Key=key)
    content = response['Body'].read().decode('utf-8')
    
    # Parse CSV and validate format
    csv_reader = csv.DictReader(StringIO(content))
    rows = list(csv_reader)
    
    # Validate required columns
    required_columns = ['Text', 'File', 'Line', 'BeginOffset', 'EndOffset', 'Type']
    if not all(col in csv_reader.fieldnames for col in required_columns):
        raise ValueError(f"Missing required columns. Expected: {required_columns}")
    
    # Validate entity types and counts
    entity_types = {}
    for row in rows:
        entity_type = row['Type']
        entity_types[entity_type] = entity_types.get(entity_type, 0) + 1
    
    # Check minimum examples per entity type
    min_examples = 5  # Reduced for demo purposes
    insufficient_types = [et for et, count in entity_types.items() if count < min_examples]
    
    if insufficient_types:
        print(f"Warning: Entity types with fewer than {min_examples} examples: {insufficient_types}")
    
    # Save processed data
    processed_key = key.replace('.csv', '_processed.csv')
    s3.put_object(
        Bucket=bucket,
        Key=processed_key,
        Body=content,
        ContentType='text/csv'
    )
    
    return {
        'processed_file': processed_key,
        'entity_types': list(entity_types.keys()),
        'total_examples': len(rows),
        'entity_counts': entity_types
    }

def process_classification_data(bucket, key):
    # Download and validate classification training data
    response = s3.get_object(Bucket=bucket, Key=key)
    content = response['Body'].read().decode('utf-8')
    
    # Parse CSV and validate format
    csv_reader = csv.DictReader(StringIO(content))
    rows = list(csv_reader)
    
    # Validate required columns
    required_columns = ['Text', 'Label']
    if not all(col in csv_reader.fieldnames for col in required_columns):
        raise ValueError(f"Missing required columns. Expected: {required_columns}")
    
    # Validate labels and counts
    label_counts = {}
    for row in rows:
        label = row['Label']
        label_counts[label] = label_counts.get(label, 0) + 1
    
    # Check minimum examples per label
    min_examples = 1  # Reduced for demo purposes
    insufficient_labels = [label for label, count in label_counts.items() if count < min_examples]
    
    if insufficient_labels:
        print(f"Warning: Labels with fewer than {min_examples} examples: {insufficient_labels}")
    
    # Save processed data
    processed_key = key.replace('.csv', '_processed.csv')
    s3.put_object(
        Bucket=bucket,
        Key=processed_key,
        Body=content,
        ContentType='text/csv'
    )
    
    return {
        'processed_file': processed_key,
        'labels': list(label_counts.keys()),
        'total_examples': len(rows),
        'label_counts': label_counts
    }
EOF
    
    # Create model trainer function
    cat > "${SCRIPT_DIR}/model_trainer.py" << 'EOF'
import json
import boto3
from datetime import datetime
import uuid

comprehend = boto3.client('comprehend')

def lambda_handler(event, context):
    bucket = event['bucket']
    model_type = event['model_type']  # 'entity' or 'classification'
    
    try:
        if model_type == 'entity':
            result = train_entity_model(event)
        elif model_type == 'classification':
            result = train_classification_model(event)
        else:
            raise ValueError(f"Invalid model type: {model_type}")
        
        return {
            'statusCode': 200,
            'model_type': model_type,
            'training_job_arn': result['EntityRecognizerArn'] if model_type == 'entity' else result['DocumentClassifierArn'],
            'training_status': 'SUBMITTED'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e),
            'model_type': model_type
        }

def train_entity_model(event):
    bucket = event['bucket']
    training_data = event['entity_training_ready']['processed_file']
    
    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    recognizer_name = f"{event.get('project_name', 'custom')}-entity-{timestamp}"
    
    # Configure training job
    training_config = {
        'RecognizerName': recognizer_name,
        'DataAccessRoleArn': event['role_arn'],
        'InputDataConfig': {
            'EntityTypes': [
                {'Type': entity_type} 
                for entity_type in event['entity_training_ready']['entity_types']
            ],
            'Documents': {
                'S3Uri': f"s3://{bucket}/training-data/entities_sample.txt"
            },
            'Annotations': {
                'S3Uri': f"s3://{bucket}/training-data/{training_data}"
            }
        },
        'LanguageCode': 'en'
    }
    
    # Start training job
    response = comprehend.create_entity_recognizer(**training_config)
    
    return response

def train_classification_model(event):
    bucket = event['bucket']
    training_data = event['classification_training_ready']['processed_file']
    
    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    classifier_name = f"{event.get('project_name', 'custom')}-classifier-{timestamp}"
    
    # Configure training job
    training_config = {
        'DocumentClassifierName': classifier_name,
        'DataAccessRoleArn': event['role_arn'],
        'InputDataConfig': {
            'S3Uri': f"s3://{bucket}/training-data/{training_data}"
        },
        'LanguageCode': 'en'
    }
    
    # Start training job
    response = comprehend.create_document_classifier(**training_config)
    
    return response
EOF
    
    # Create status checker function
    cat > "${SCRIPT_DIR}/status_checker.py" << 'EOF'
import json
import boto3

comprehend = boto3.client('comprehend')

def lambda_handler(event, context):
    model_type = event['model_type']
    job_arn = event['training_job_arn']
    
    try:
        if model_type == 'entity':
            response = comprehend.describe_entity_recognizer(
                EntityRecognizerArn=job_arn
            )
            status = response['EntityRecognizerProperties']['Status']
            
        elif model_type == 'classification':
            response = comprehend.describe_document_classifier(
                DocumentClassifierArn=job_arn
            )
            status = response['DocumentClassifierProperties']['Status']
        
        else:
            raise ValueError(f"Invalid model type: {model_type}")
        
        # Determine if training is complete
        is_complete = status in ['TRAINED', 'TRAINING_FAILED', 'STOPPED']
        
        return {
            'statusCode': 200,
            'model_type': model_type,
            'training_job_arn': job_arn,
            'training_status': status,
            'is_complete': is_complete,
            'model_details': response
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e),
            'model_type': model_type,
            'training_job_arn': job_arn
        }
EOF
    
    # Create inference API function
    cat > "${SCRIPT_DIR}/inference_api.py" << 'EOF'
import json
import boto3
from datetime import datetime
import os
import uuid

comprehend = boto3.client('comprehend')

def lambda_handler(event, context):
    try:
        # Parse request
        body = json.loads(event.get('body', '{}'))
        text = body.get('text', '')
        entity_model_arn = body.get('entity_model_arn')
        classifier_model_arn = body.get('classifier_model_arn')
        
        if not text:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Text is required'})
            }
        
        results = {}
        
        # Perform entity recognition if model is provided
        if entity_model_arn:
            entity_results = comprehend.detect_entities(
                Text=text,
                EndpointArn=entity_model_arn
            )
            results['entities'] = entity_results['Entities']
        
        # Perform classification if model is provided
        if classifier_model_arn:
            classification_results = comprehend.classify_document(
                Text=text,
                EndpointArn=classifier_model_arn
            )
            results['classification'] = classification_results['Classes']
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'text': text,
                'results': results,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create deployment packages and Lambda functions
    for func_name in "data_preprocessor" "model_trainer" "status_checker" "inference_api"; do
        log "Creating Lambda function: ${PROJECT_NAME}-${func_name}"
        
        cd "$SCRIPT_DIR"
        zip "${func_name}.zip" "${func_name}.py"
        
        # Check if function already exists
        if aws lambda get-function --function-name "${PROJECT_NAME}-${func_name}" &>/dev/null; then
            log "Lambda function ${PROJECT_NAME}-${func_name} already exists, updating..."
            aws lambda update-function-code \
                --function-name "${PROJECT_NAME}-${func_name}" \
                --zip-file "fileb://${func_name}.zip"
        else
            aws lambda create-function \
                --function-name "${PROJECT_NAME}-${func_name}" \
                --runtime python3.9 \
                --role "$ROLE_ARN" \
                --handler "${func_name}.lambda_handler" \
                --zip-file "fileb://${func_name}.zip" \
                --timeout $([ "$func_name" = "data_preprocessor" ] && echo 300 || echo 60)
        fi
        
        rm "${func_name}.zip"
    done
    
    log "✅ Created all Lambda functions"
}

# Create Step Functions workflow
create_step_functions() {
    log "Creating Step Functions workflow..."
    
    # Create workflow definition
    cat > "${SCRIPT_DIR}/training_workflow.json" << EOF
{
  "Comment": "Comprehend Custom Model Training Pipeline",
  "StartAt": "PreprocessData",
  "States": {
    "PreprocessData": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-data-preprocessor",
        "Payload": {
          "bucket": "${BUCKET_NAME}",
          "entity_training_data": "training-data/entities.csv",
          "classification_training_data": "training-data/classification.csv"
        }
      },
      "ResultPath": "$.preprocessing_result",
      "Next": "TrainEntityModel"
    },
    "TrainEntityModel": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-model-trainer",
        "Payload": {
          "bucket": "${BUCKET_NAME}",
          "model_type": "entity",
          "project_name": "${PROJECT_NAME}",
          "role_arn": "${ROLE_ARN}",
          "entity_training_ready.$": "$.preprocessing_result.Payload.entity_training_ready"
        }
      },
      "ResultPath": "$.entity_training_result",
      "Next": "TrainClassificationModel"
    },
    "TrainClassificationModel": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-model-trainer",
        "Payload": {
          "bucket": "${BUCKET_NAME}",
          "model_type": "classification",
          "project_name": "${PROJECT_NAME}",
          "role_arn": "${ROLE_ARN}",
          "classification_training_ready.$": "$.preprocessing_result.Payload.classification_training_ready"
        }
      },
      "ResultPath": "$.classification_training_result",
      "Next": "WaitForTraining"
    },
    "WaitForTraining": {
      "Type": "Wait",
      "Seconds": 300,
      "Next": "CheckEntityModelStatus"
    },
    "CheckEntityModelStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-status-checker",
        "Payload": {
          "model_type": "entity",
          "training_job_arn.$": "$.entity_training_result.Payload.training_job_arn"
        }
      },
      "ResultPath": "$.entity_status_result",
      "Next": "CheckClassificationModelStatus"
    },
    "CheckClassificationModelStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-status-checker",
        "Payload": {
          "model_type": "classification",
          "training_job_arn.$": "$.classification_training_result.Payload.training_job_arn"
        }
      },
      "ResultPath": "$.classification_status_result",
      "Next": "CheckAllModelsComplete"
    },
    "CheckAllModelsComplete": {
      "Type": "Choice",
      "Choices": [
        {
          "And": [
            {
              "Variable": "$.entity_status_result.Payload.is_complete",
              "BooleanEquals": true
            },
            {
              "Variable": "$.classification_status_result.Payload.is_complete",
              "BooleanEquals": true
            }
          ],
          "Next": "TrainingComplete"
        }
      ],
      "Default": "WaitForTraining"
    },
    "TrainingComplete": {
      "Type": "Pass",
      "Result": "Training pipeline completed successfully",
      "End": true
    }
  }
}
EOF
    
    # Check if state machine already exists
    STATE_MACHINE_NAME="${PROJECT_NAME}-training-pipeline"
    if aws stepfunctions describe-state-machine --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" &>/dev/null; then
        log "Step Functions state machine already exists, updating..."
        aws stepfunctions update-state-machine \
            --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
            --definition "file://${SCRIPT_DIR}/training_workflow.json"
        STATE_MACHINE_ARN="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"
    else
        STATE_MACHINE_ARN=$(aws stepfunctions create-state-machine \
            --name "$STATE_MACHINE_NAME" \
            --definition "file://${SCRIPT_DIR}/training_workflow.json" \
            --role-arn "$ROLE_ARN" \
            --query 'stateMachineArn' --output text)
    fi
    
    # Save state machine ARN for later use
    echo "STATE_MACHINE_ARN=$STATE_MACHINE_ARN" >> "${SCRIPT_DIR}/.env"
    
    log "✅ Created Step Functions workflow: $STATE_MACHINE_ARN"
}

# Start training pipeline
start_training() {
    log "Starting training pipeline..."
    
    # Load environment variables
    source "${SCRIPT_DIR}/.env"
    
    # Start execution
    EXECUTION_NAME="training-$(date +%Y%m%d-%H%M%S)"
    EXECUTION_ARN=$(aws stepfunctions start-execution \
        --state-machine-arn "$STATE_MACHINE_ARN" \
        --name "$EXECUTION_NAME" \
        --query 'executionArn' --output text)
    
    echo "EXECUTION_ARN=$EXECUTION_ARN" >> "${SCRIPT_DIR}/.env"
    
    log "✅ Started training pipeline: $EXECUTION_ARN"
    log "Training will take 1-4 hours. Monitor progress:"
    log "  AWS Console: https://${AWS_REGION}.console.aws.amazon.com/states/home?region=${AWS_REGION}#/executions/details/${EXECUTION_ARN}"
    log "  CLI: aws stepfunctions describe-execution --execution-arn ${EXECUTION_ARN}"
}

# Main deployment function
main() {
    log "Starting deployment of Custom Entity Recognition and Classification with Comprehend"
    log "=================================================================="
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_role
    create_training_data
    create_lambda_functions
    create_step_functions
    start_training
    
    log "=================================================================="
    log "✅ Deployment completed successfully!"
    log ""
    log "Next Steps:"
    log "1. Monitor training progress in Step Functions console"
    log "2. Training typically takes 1-4 hours to complete"
    log "3. After training completes, you can deploy API Gateway for inference"
    log "4. Use the destroy.sh script to clean up resources when finished"
    log ""
    log "Environment saved to: ${SCRIPT_DIR}/.env"
    log "Logs saved to: $LOG_FILE"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi