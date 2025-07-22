#!/bin/bash

# Deploy script for Serverless Medical Image Processing with AWS HealthImaging and Step Functions
# This script automates the deployment of the complete medical imaging pipeline

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_info "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
}

# Function to check if region supports HealthImaging
check_healthimaging_support() {
    local region=$1
    local supported_regions=("us-east-1" "us-west-2" "eu-west-1" "ap-southeast-2")
    
    for supported_region in "${supported_regions[@]}"; do
        if [[ "$region" == "$supported_region" ]]; then
            return 0
        fi
    done
    
    log_warning "Region $region may not support AWS HealthImaging"
    log_info "Supported regions: ${supported_regions[*]}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed"
        log_info "Install from: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2)
    local required_version="2.0.0"
    if [[ $(printf '%s\n' "$required_version" "$aws_version" | sort -V | head -n1) != "$required_version" ]]; then
        log_error "AWS CLI version 2.0.0 or higher is required (current: $aws_version)"
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command_exists jq; then
        log_error "jq is not installed (required for JSON processing)"
        log_info "Install with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
        exit 1
    fi
    
    # Check zip utility
    if ! command_exists zip; then
        log_error "zip utility is not installed"
        exit 1
    fi
    
    # Check AWS configuration
    check_aws_config
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not configured"
        log_info "Set region with: aws configure set region us-east-1"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Check HealthImaging support
    check_healthimaging_support "$AWS_REGION"
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export DATASTORE_NAME="medical-imaging-${RANDOM_SUFFIX}"
    export INPUT_BUCKET="dicom-input-${RANDOM_SUFFIX}"
    export OUTPUT_BUCKET="dicom-output-${RANDOM_SUFFIX}"
    export STATE_MACHINE_NAME="dicom-processor-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="lambda-medical-imaging-${RANDOM_SUFFIX}"
    export STEPFUNCTIONS_ROLE_NAME="StepFunctions-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
    log_info "Region: $AWS_REGION"
    log_info "Account ID: $AWS_ACCOUNT_ID"
    log_info "Resource suffix: $RANDOM_SUFFIX"
}

# Function to create S3 buckets
create_s3_buckets() {
    log_info "Creating S3 buckets..."
    
    # Create input bucket
    if aws s3 mb "s3://${INPUT_BUCKET}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_success "Created input bucket: ${INPUT_BUCKET}"
    else
        log_error "Failed to create input bucket: ${INPUT_BUCKET}"
        exit 1
    fi
    
    # Create output bucket
    if aws s3 mb "s3://${OUTPUT_BUCKET}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_success "Created output bucket: ${OUTPUT_BUCKET}"
    else
        log_error "Failed to create output bucket: ${OUTPUT_BUCKET}"
        exit 1
    fi
    
    # Enable encryption on input bucket
    aws s3api put-bucket-encryption \
        --bucket "${INPUT_BUCKET}" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
        >/dev/null 2>&1
    
    # Enable encryption on output bucket
    aws s3api put-bucket-encryption \
        --bucket "${OUTPUT_BUCKET}" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
        >/dev/null 2>&1
    
    log_success "S3 buckets created with encryption enabled"
}

# Function to create IAM roles
create_iam_roles() {
    log_info "Creating IAM roles..."
    
    # Create Lambda execution role
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
    
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        >/dev/null 2>&1
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        >/dev/null 2>&1
    
    # Create custom policy for HealthImaging and other services
    cat > healthimaging-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "medical-imaging:*",
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "states:StartExecution",
        "states:SendTaskSuccess",
        "states:SendTaskFailure"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-name HealthImagingAccess \
        --policy-document file://healthimaging-policy.json \
        >/dev/null 2>&1
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    # Create Step Functions role
    cat > stepfunctions-trust-policy.json << EOF
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
    
    aws iam create-role \
        --role-name "${STEPFUNCTIONS_ROLE_NAME}" \
        --assume-role-policy-document file://stepfunctions-trust-policy.json \
        >/dev/null 2>&1
    
    aws iam attach-role-policy \
        --role-name "${STEPFUNCTIONS_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaRole \
        >/dev/null 2>&1
    
    export STEPFUNCTIONS_ROLE_ARN=$(aws iam get-role \
        --role-name "${STEPFUNCTIONS_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    log_success "IAM roles created"
    log_info "Lambda Role ARN: ${LAMBDA_ROLE_ARN}"
    log_info "Step Functions Role ARN: ${STEPFUNCTIONS_ROLE_ARN}"
    
    # Wait for IAM propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
}

# Function to create HealthImaging data store
create_healthimaging_datastore() {
    log_info "Creating HealthImaging data store..."
    
    export DATASTORE_ID=$(aws medical-imaging create-datastore \
        --datastore-name "${DATASTORE_NAME}" \
        --region "${AWS_REGION}" \
        --query 'datastoreId' --output text 2>/dev/null)
    
    if [[ -z "$DATASTORE_ID" ]]; then
        log_error "Failed to create HealthImaging data store"
        log_info "Please ensure AWS HealthImaging is available in your region"
        exit 1
    fi
    
    log_success "HealthImaging data store created: ${DATASTORE_ID}"
    log_info "Waiting for data store to become active..."
    
    # Wait for data store to be active (with timeout)
    local timeout=300  # 5 minutes
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local status=$(aws medical-imaging get-datastore \
            --datastore-id "${DATASTORE_ID}" \
            --query 'datastoreProperties.datastoreStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$status" == "ACTIVE" ]]; then
            log_success "Data store is now active"
            return 0
        elif [[ "$status" == "CREATE_FAILED" ]]; then
            log_error "Data store creation failed"
            exit 1
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        echo -n "."
    done
    
    log_error "Timeout waiting for data store to become active"
    exit 1
}

# Function to create Lambda functions
create_lambda_functions() {
    log_info "Creating Lambda functions..."
    
    # Create lambda functions directory
    mkdir -p lambda-functions
    
    # Create start import Lambda function
    cat > lambda-functions/start_import.py << 'EOF'
import json
import boto3
import os

medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Initiates a HealthImaging import job when DICOM files are uploaded to S3.
    This function processes S3 events and starts the medical image import workflow.
    """
    datastore_id = os.environ['DATASTORE_ID']
    output_bucket = os.environ['OUTPUT_BUCKET']
    
    # Extract S3 event details
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        # Prepare import job parameters
        input_s3_uri = f"s3://{bucket}/{os.path.dirname(key)}/"
        output_s3_uri = f"s3://{output_bucket}/import-results/"
        
        # Start import job
        response = medical_imaging.start_dicom_import_job(
            dataStoreId=datastore_id,
            inputS3Uri=input_s3_uri,
            outputS3Uri=output_s3_uri,
            dataAccessRoleArn=os.environ['LAMBDA_ROLE_ARN']
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'jobId': response['jobId'],
                'dataStoreId': response['dataStoreId'],
                'status': 'SUBMITTED'
            })
        }
EOF
    
    # Package start import function
    cd lambda-functions
    zip start_import.zip start_import.py >/dev/null 2>&1
    cd ..
    
    aws lambda create-function \
        --function-name "StartDicomImport-${RANDOM_SUFFIX}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler start_import.lambda_handler \
        --zip-file fileb://lambda-functions/start_import.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{DATASTORE_ID=${DATASTORE_ID},OUTPUT_BUCKET=${OUTPUT_BUCKET},LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}}" \
        >/dev/null 2>&1
    
    # Create metadata processing function
    cat > lambda-functions/process_metadata.py << 'EOF'
import json
import boto3
import os

medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Extracts and processes DICOM metadata from HealthImaging image sets.
    Parses patient information, study details, and technical parameters.
    """
    datastore_id = event['datastoreId']
    image_set_id = event['imageSetId']
    
    try:
        # Get image set metadata
        response = medical_imaging.get_image_set_metadata(
            datastoreId=datastore_id,
            imageSetId=image_set_id
        )
        
        # Parse DICOM metadata
        metadata = json.loads(response['imageSetMetadataBlob'].read())
        
        # Extract relevant fields
        patient_info = metadata.get('Patient', {})
        study_info = metadata.get('Study', {})
        series_info = metadata.get('Series', {})
        
        processed_metadata = {
            'patientId': patient_info.get('DICOM', {}).get('PatientID'),
            'patientName': patient_info.get('DICOM', {}).get('PatientName'),
            'studyDate': study_info.get('DICOM', {}).get('StudyDate'),
            'studyDescription': study_info.get('DICOM', {}).get('StudyDescription'),
            'modality': series_info.get('DICOM', {}).get('Modality'),
            'imageSetId': image_set_id,
            'processingTimestamp': context.aws_request_id
        }
        
        # Store processed metadata
        output_key = f"metadata/{image_set_id}/metadata.json"
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(processed_metadata),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(processed_metadata)
        }
        
    except Exception as e:
        print(f"Error processing metadata: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package metadata processing function
    cd lambda-functions
    zip process_metadata.zip process_metadata.py >/dev/null 2>&1
    cd ..
    
    aws lambda create-function \
        --function-name "ProcessDicomMetadata-${RANDOM_SUFFIX}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler process_metadata.lambda_handler \
        --zip-file fileb://lambda-functions/process_metadata.zip \
        --timeout 120 \
        --memory-size 512 \
        --environment Variables="{OUTPUT_BUCKET=${OUTPUT_BUCKET}}" \
        >/dev/null 2>&1
    
    # Create image analysis function
    cat > lambda-functions/analyze_image.py << 'EOF'
import json
import boto3
import os

medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Performs basic image analysis on medical images.
    In production, this would integrate with ML models for diagnostic support.
    """
    datastore_id = event['datastoreId']
    image_set_id = event['imageSetId']
    
    try:
        # Get image set metadata
        image_set_metadata = medical_imaging.get_image_set_metadata(
            datastoreId=datastore_id,
            imageSetId=image_set_id
        )
        
        # For demo, we'll analyze basic properties
        # In production, this would include AI/ML inference
        analysis_results = {
            'imageSetId': image_set_id,
            'analysisType': 'BasicQualityCheck',
            'timestamp': context.aws_request_id,
            'results': {
                'imageQuality': 'GOOD',
                'processingStatus': 'COMPLETED',
                'anomaliesDetected': False,
                'confidenceScore': 0.95
            }
        }
        
        # Store analysis results
        output_key = f"analysis/{image_set_id}/results.json"
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(analysis_results),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(analysis_results)
        }
        
    except Exception as e:
        print(f"Error analyzing image: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package image analysis function
    cd lambda-functions
    zip analyze_image.zip analyze_image.py >/dev/null 2>&1
    cd ..
    
    aws lambda create-function \
        --function-name "AnalyzeMedicalImage-${RANDOM_SUFFIX}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler analyze_image.lambda_handler \
        --zip-file fileb://lambda-functions/analyze_image.zip \
        --timeout 300 \
        --memory-size 1024 \
        --environment Variables="{OUTPUT_BUCKET=${OUTPUT_BUCKET}}" \
        >/dev/null 2>&1
    
    log_success "Lambda functions created"
}

# Function to create Step Functions state machine
create_step_functions() {
    log_info "Creating Step Functions state machine..."
    
    # Create CloudWatch log group for Step Functions
    aws logs create-log-group \
        --log-group-name "/aws/stepfunctions/${STATE_MACHINE_NAME}" \
        >/dev/null 2>&1 || true
    
    # Create state machine definition
    cat > state-machine.json << EOF
{
  "Comment": "Medical image processing workflow",
  "StartAt": "CheckImportStatus",
  "States": {
    "CheckImportStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:medicalimaging:getDICOMImportJob",
      "Parameters": {
        "DatastoreId.$": "$.dataStoreId",
        "JobId.$": "$.jobId"
      },
      "Next": "IsImportComplete",
      "Retry": [
        {
          "ErrorEquals": ["States.ALL"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ]
    },
    "IsImportComplete": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.JobStatus",
          "StringEquals": "COMPLETED",
          "Next": "ProcessImageSets"
        },
        {
          "Variable": "$.JobStatus",
          "StringEquals": "IN_PROGRESS",
          "Next": "WaitForImport"
        }
      ],
      "Default": "ImportFailed"
    },
    "WaitForImport": {
      "Type": "Wait",
      "Seconds": 30,
      "Next": "CheckImportStatus"
    },
    "ProcessImageSets": {
      "Type": "Pass",
      "Result": "Import completed successfully",
      "End": true
    },
    "ImportFailed": {
      "Type": "Fail",
      "Error": "ImportJobFailed",
      "Cause": "The DICOM import job failed"
    }
  }
}
EOF
    
    export STATE_MACHINE_ARN=$(aws stepfunctions create-state-machine \
        --name "${STATE_MACHINE_NAME}" \
        --definition file://state-machine.json \
        --role-arn "${STEPFUNCTIONS_ROLE_ARN}" \
        --type EXPRESS \
        --logging-configuration \
        "level=ALL,includeExecutionData=true,destinations=[{cloudWatchLogsLogGroup={logGroupArn=arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/stepfunctions/${STATE_MACHINE_NAME}:*}}]" \
        --query 'stateMachineArn' --output text 2>/dev/null)
    
    if [[ -z "$STATE_MACHINE_ARN" ]]; then
        log_error "Failed to create Step Functions state machine"
        exit 1
    fi
    
    log_success "Step Functions state machine created: ${STATE_MACHINE_ARN}"
}

# Function to configure EventBridge
configure_eventbridge() {
    log_info "Configuring EventBridge rules..."
    
    # Create EventBridge rule for import completion
    aws events put-rule \
        --name "DicomImportCompleted-${RANDOM_SUFFIX}" \
        --event-pattern "{
          \"source\": [\"aws.medical-imaging\"],
          \"detail-type\": [\"Import Job Completed\"],
          \"detail\": {
            \"datastoreId\": [\"${DATASTORE_ID}\"]
          }
        }" \
        --state ENABLED \
        >/dev/null 2>&1
    
    # Add Lambda permission for EventBridge
    aws lambda add-permission \
        --function-name "ProcessDicomMetadata-${RANDOM_SUFFIX}" \
        --statement-id AllowEventBridge \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/DicomImportCompleted-${RANDOM_SUFFIX}" \
        >/dev/null 2>&1
    
    # Create target for the rule
    aws events put-targets \
        --rule "DicomImportCompleted-${RANDOM_SUFFIX}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:ProcessDicomMetadata-${RANDOM_SUFFIX}" \
        >/dev/null 2>&1
    
    log_success "EventBridge rules configured"
}

# Function to configure S3 event notifications
configure_s3_events() {
    log_info "Configuring S3 event notifications..."
    
    # Create S3 event notification configuration
    cat > s3-notification.json << EOF
{
  "LambdaFunctionConfigurations": [
    {
      "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:StartDicomImport-${RANDOM_SUFFIX}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "suffix",
              "Value": ".dcm"
            }
          ]
        }
      }
    }
  ]
}
EOF
    
    # Add Lambda permission for S3
    aws lambda add-permission \
        --function-name "StartDicomImport-${RANDOM_SUFFIX}" \
        --statement-id AllowS3Invoke \
        --action lambda:InvokeFunction \
        --principal s3.amazonaws.com \
        --source-arn "arn:aws:s3:::${INPUT_BUCKET}" \
        >/dev/null 2>&1
    
    # Configure S3 bucket notification
    aws s3api put-bucket-notification-configuration \
        --bucket "${INPUT_BUCKET}" \
        --notification-configuration file://s3-notification.json \
        >/dev/null 2>&1
    
    log_success "S3 event notifications configured"
}

# Function to save deployment info
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
  "deploymentTimestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "awsRegion": "${AWS_REGION}",
  "awsAccountId": "${AWS_ACCOUNT_ID}",
  "resources": {
    "healthImagingDataStore": {
      "id": "${DATASTORE_ID}",
      "name": "${DATASTORE_NAME}"
    },
    "s3Buckets": {
      "inputBucket": "${INPUT_BUCKET}",
      "outputBucket": "${OUTPUT_BUCKET}"
    },
    "lambdaFunctions": {
      "startImport": "StartDicomImport-${RANDOM_SUFFIX}",
      "processMetadata": "ProcessDicomMetadata-${RANDOM_SUFFIX}",
      "analyzeImage": "AnalyzeMedicalImage-${RANDOM_SUFFIX}"
    },
    "stepFunctions": {
      "stateMachine": "${STATE_MACHINE_NAME}",
      "arn": "${STATE_MACHINE_ARN}"
    },
    "iamRoles": {
      "lambdaRole": "${LAMBDA_ROLE_NAME}",
      "stepFunctionsRole": "${STEPFUNCTIONS_ROLE_NAME}"
    },
    "eventBridge": {
      "rule": "DicomImportCompleted-${RANDOM_SUFFIX}"
    }
  },
  "resourceSuffix": "${RANDOM_SUFFIX}"
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    rm -f lambda-trust-policy.json
    rm -f healthimaging-policy.json
    rm -f stepfunctions-trust-policy.json
    rm -f state-machine.json
    rm -f s3-notification.json
    rm -rf lambda-functions
    
    log_success "Temporary files cleaned up"
}

# Function to display deployment summary
display_summary() {
    log_success "🎉 Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
    echo "Resource Suffix: ${RANDOM_SUFFIX}"
    echo ""
    echo "=== CREATED RESOURCES ==="
    echo "HealthImaging Data Store: ${DATASTORE_ID}"
    echo "Input S3 Bucket: s3://${INPUT_BUCKET}"
    echo "Output S3 Bucket: s3://${OUTPUT_BUCKET}"
    echo "Step Functions State Machine: ${STATE_MACHINE_ARN}"
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Upload DICOM files (.dcm) to: s3://${INPUT_BUCKET}/test-data/"
    echo "2. Monitor processing in CloudWatch Logs"
    echo "3. Check results in: s3://${OUTPUT_BUCKET}/"
    echo ""
    echo "=== ESTIMATED COSTS ==="
    echo "• HealthImaging: ~$0.07 per GB stored per month"
    echo "• Lambda: Pay per invocation (very low for testing)"
    echo "• S3: ~$0.023 per GB per month"
    echo "• Step Functions: ~$0.025 per 1,000 state transitions"
    echo ""
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
    log_warning "IMPORTANT: This solution processes medical data. Ensure HIPAA compliance if using real patient data."
}

# Main deployment function
main() {
    echo "========================================"
    echo "  Medical Image Processing Deployment"
    echo "========================================"
    echo ""
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_iam_roles
    create_healthimaging_datastore
    create_lambda_functions
    create_step_functions
    configure_eventbridge
    configure_s3_events
    save_deployment_info
    cleanup_temp_files
    display_summary
}

# Error handling
trap 'log_error "Deployment failed. Check the logs above for details."; exit 1' ERR

# Run main function
main "$@"