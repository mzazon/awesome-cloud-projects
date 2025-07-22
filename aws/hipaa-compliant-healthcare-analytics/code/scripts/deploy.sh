#!/bin/bash

# Healthcare Data Processing Pipelines with AWS HealthLake - Deployment Script
# This script deploys the complete healthcare data processing pipeline
# including HealthLake datastore, Lambda functions, EventBridge rules, and S3 buckets

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

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
    echo -e "[${TIMESTAMP}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "${BLUE}$*${NC}"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code ${exit_code}"
    log_error "Check ${LOG_FILE} for detailed error information"
    log_info "Run ./destroy.sh to clean up any partially created resources"
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -r, --region REGION     AWS region (default: current configured region)"
    echo "  -p, --prefix PREFIX     Resource name prefix (default: healthcare-pipeline)"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --region us-east-1 --prefix my-healthcare"
    exit 1
}

# Parse command line arguments
RESOURCE_PREFIX="healthcare-pipeline"
AWS_REGION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -p|--prefix)
            RESOURCE_PREFIX="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: ${AWS_CLI_VERSION}"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS region if not specified
    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            log_error "AWS region not configured. Set default region or use --region option."
            exit 1
        fi
    fi
    
    # Check required tools
    for tool in jq curl zip; do
        if ! command -v ${tool} &> /dev/null; then
            log_error "${tool} is required but not installed"
            exit 1
        fi
    done
    
    # Check if HealthLake is available in region
    if ! aws healthlake list-fhir-datastores --region "${AWS_REGION}" &> /dev/null; then
        log_error "AWS HealthLake is not available in region ${AWS_REGION}"
        log_error "HealthLake is available in: us-east-1, us-west-2"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Generate environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export DATASTORE_NAME="${RESOURCE_PREFIX}-fhir-datastore-${RANDOM_SUFFIX}"
    export INPUT_BUCKET="${RESOURCE_PREFIX}-input-${RANDOM_SUFFIX}"
    export OUTPUT_BUCKET="${RESOURCE_PREFIX}-output-${RANDOM_SUFFIX}"
    export LAMBDA_PROCESSOR_NAME="${RESOURCE_PREFIX}-processor-${RANDOM_SUFFIX}"
    export LAMBDA_ANALYTICS_NAME="${RESOURCE_PREFIX}-analytics-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="HealthLakeServiceRole-${RANDOM_SUFFIX}"
    export LAMBDA_EXECUTION_ROLE="LambdaExecutionRole-${RANDOM_SUFFIX}"
    
    # Save environment to file for destroy script
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DATASTORE_NAME=${DATASTORE_NAME}
INPUT_BUCKET=${INPUT_BUCKET}
OUTPUT_BUCKET=${OUTPUT_BUCKET}
LAMBDA_PROCESSOR_NAME=${LAMBDA_PROCESSOR_NAME}
LAMBDA_ANALYTICS_NAME=${LAMBDA_ANALYTICS_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
LAMBDA_EXECUTION_ROLE=${LAMBDA_EXECUTION_ROLE}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment setup completed"
    log_info "Resource prefix: ${RESOURCE_PREFIX}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Account ID: ${AWS_ACCOUNT_ID}"
}

# Create S3 buckets
create_s3_buckets() {
    log_info "Creating S3 buckets..."
    
    # Create input bucket
    if aws s3api head-bucket --bucket "${INPUT_BUCKET}" 2>/dev/null; then
        log_warn "Input bucket ${INPUT_BUCKET} already exists"
    else
        aws s3 mb "s3://${INPUT_BUCKET}" --region "${AWS_REGION}"
        log_success "Created input bucket: ${INPUT_BUCKET}"
    fi
    
    # Create output bucket
    if aws s3api head-bucket --bucket "${OUTPUT_BUCKET}" 2>/dev/null; then
        log_warn "Output bucket ${OUTPUT_BUCKET} already exists"
    else
        aws s3 mb "s3://${OUTPUT_BUCKET}" --region "${AWS_REGION}"
        log_success "Created output bucket: ${OUTPUT_BUCKET}"
    fi
    
    # Configure bucket settings
    for bucket in "${INPUT_BUCKET}" "${OUTPUT_BUCKET}"; do
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "${bucket}" \
            --versioning-configuration Status=Enabled
        
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "${bucket}" \
            --server-side-encryption-configuration \
            'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "${bucket}" \
            --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    done
    
    log_success "S3 buckets configured with encryption and versioning"
}

# Create sample FHIR data
create_sample_data() {
    log_info "Creating sample FHIR data..."
    
    cat > "${SCRIPT_DIR}/patient-sample.json" << 'EOF'
{
  "resourceType": "Patient",
  "id": "patient-001",
  "active": true,
  "name": [
    {
      "use": "usual",
      "family": "Doe",
      "given": ["John"]
    }
  ],
  "telecom": [
    {
      "system": "phone",
      "value": "(555) 123-4567",
      "use": "home"
    }
  ],
  "gender": "male",
  "birthDate": "1985-03-15",
  "address": [
    {
      "use": "home",
      "line": ["123 Main St"],
      "city": "Anytown",
      "state": "CA",
      "postalCode": "12345"
    }
  ]
}
EOF
    
    # Upload sample data
    aws s3 cp "${SCRIPT_DIR}/patient-sample.json" "s3://${INPUT_BUCKET}/fhir-data/"
    log_success "Sample FHIR data uploaded to S3"
}

# Create IAM role for HealthLake
create_healthlake_iam_role() {
    log_info "Creating IAM role for HealthLake..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        log_warn "IAM role ${IAM_ROLE_NAME} already exists"
        export HEALTHLAKE_ROLE_ARN=$(aws iam get-role --role-name "${IAM_ROLE_NAME}" --query 'Role.Arn' --output text)
        return
    fi
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/healthlake-trust-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "healthlake.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document "file://${SCRIPT_DIR}/healthlake-trust-policy.json"
    
    # Create S3 access policy
    cat > "${SCRIPT_DIR}/healthlake-s3-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${INPUT_BUCKET}/*",
        "arn:aws:s3:::${OUTPUT_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${INPUT_BUCKET}",
        "arn:aws:s3:::${OUTPUT_BUCKET}"
      ]
    }
  ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name HealthLakeS3Access \
        --policy-document "file://${SCRIPT_DIR}/healthlake-s3-policy.json"
    
    # Get role ARN
    export HEALTHLAKE_ROLE_ARN=$(aws iam get-role --role-name "${IAM_ROLE_NAME}" --query 'Role.Arn' --output text)
    
    # Wait for role to be available
    sleep 10
    
    log_success "HealthLake IAM role created: ${HEALTHLAKE_ROLE_ARN}"
}

# Create HealthLake datastore
create_healthlake_datastore() {
    log_info "Creating HealthLake FHIR datastore..."
    
    # Check if datastore already exists
    if aws healthlake list-fhir-datastores --query "DatastorePropertiesList[?DatastoreName=='${DATASTORE_NAME}']" --output text | grep -q "${DATASTORE_NAME}"; then
        log_warn "HealthLake datastore ${DATASTORE_NAME} already exists"
        export DATASTORE_ID=$(aws healthlake list-fhir-datastores --query "DatastorePropertiesList[?DatastoreName=='${DATASTORE_NAME}'].DatastoreId" --output text)
    else
        # Create datastore
        aws healthlake create-fhir-datastore \
            --datastore-name "${DATASTORE_NAME}" \
            --datastore-type-version R4 \
            --preload-data-config PreloadDataType=SYNTHEA
        
        export DATASTORE_ID=$(aws healthlake list-fhir-datastores \
            --query "DatastorePropertiesList[?DatastoreName=='${DATASTORE_NAME}'].DatastoreId" \
            --output text)
    fi
    
    # Wait for datastore to become active
    log_info "Waiting for HealthLake datastore to become active..."
    while true; do
        DATASTORE_STATUS=$(aws healthlake describe-fhir-datastore \
            --datastore-id "${DATASTORE_ID}" \
            --query 'DatastoreProperties.DatastoreStatus' \
            --output text)
        
        if [[ "$DATASTORE_STATUS" == "ACTIVE" ]]; then
            break
        elif [[ "$DATASTORE_STATUS" == "FAILED" ]]; then
            log_error "HealthLake datastore creation failed"
            exit 1
        else
            log_info "Datastore status: $DATASTORE_STATUS"
            sleep 30
        fi
    done
    
    export DATASTORE_ENDPOINT=$(aws healthlake describe-fhir-datastore \
        --datastore-id "${DATASTORE_ID}" \
        --query 'DatastoreProperties.DatastoreEndpoint' \
        --output text)
    
    log_success "HealthLake datastore created: ${DATASTORE_ID}"
    log_info "Datastore endpoint: ${DATASTORE_ENDPOINT}"
}

# Create Lambda functions
create_lambda_functions() {
    log_info "Creating Lambda functions..."
    
    # Create Lambda execution role if it doesn't exist
    if ! aws iam get-role --role-name "${LAMBDA_EXECUTION_ROLE}" &>/dev/null; then
        cat > "${SCRIPT_DIR}/lambda-trust-policy.json" << 'EOF'
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
            --role-name "${LAMBDA_EXECUTION_ROLE}" \
            --assume-role-policy-document "file://${SCRIPT_DIR}/lambda-trust-policy.json"
        
        aws iam attach-role-policy \
            --role-name "${LAMBDA_EXECUTION_ROLE}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        # Add S3 permissions for analytics function
        cat > "${SCRIPT_DIR}/lambda-s3-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::${OUTPUT_BUCKET}/*"
    }
  ]
}
EOF
        
        aws iam put-role-policy \
            --role-name "${LAMBDA_EXECUTION_ROLE}" \
            --policy-name LambdaS3Access \
            --policy-document "file://${SCRIPT_DIR}/lambda-s3-policy.json"
        
        sleep 10  # Wait for role propagation
    fi
    
    # Create processor function code
    cat > "${SCRIPT_DIR}/lambda-processor.py" << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

healthlake = boto3.client('healthlake')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Process HealthLake events from EventBridge
    """
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Extract event details
        event_source = event.get('source')
        event_type = event.get('detail-type')
        event_detail = event.get('detail', {})
        
        if event_source == 'aws.healthlake':
            if 'Import Job' in event_type:
                process_import_job_event(event_detail)
            elif 'Export Job' in event_type:
                process_export_job_event(event_detail)
            elif 'Data Store' in event_type:
                process_datastore_event(event_detail)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Event processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def process_import_job_event(event_detail):
    """Process import job status changes"""
    job_status = event_detail.get('jobStatus')
    job_id = event_detail.get('jobId')
    
    logger.info(f"Import job {job_id} status: {job_status}")
    
    if job_status == 'COMPLETED':
        logger.info(f"Import job {job_id} completed successfully")
    elif job_status == 'FAILED':
        logger.error(f"Import job {job_id} failed")

def process_export_job_event(event_detail):
    """Process export job status changes"""
    job_status = event_detail.get('jobStatus')
    job_id = event_detail.get('jobId')
    
    logger.info(f"Export job {job_id} status: {job_status}")

def process_datastore_event(event_detail):
    """Process datastore status changes"""
    datastore_status = event_detail.get('datastoreStatus')
    datastore_id = event_detail.get('datastoreId')
    
    logger.info(f"Datastore {datastore_id} status: {datastore_status}")
EOF
    
    # Create analytics function code
    cat > "${SCRIPT_DIR}/lambda-analytics.py" << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Generate analytics reports from HealthLake data
    """
    try:
        logger.info("Starting analytics processing")
        
        # Generate sample analytics report
        report = generate_patient_analytics()
        
        # Save report to S3
        report_key = f"analytics/patient-report-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
        
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=report_key,
            Body=json.dumps(report, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Analytics report saved to s3://{os.environ['OUTPUT_BUCKET']}/{report_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Analytics processing completed')
        }
        
    except Exception as e:
        logger.error(f"Error in analytics processing: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def generate_patient_analytics():
    """Generate sample patient analytics"""
    return {
        'report_type': 'patient_summary',
        'generated_at': datetime.now().isoformat(),
        'metrics': {
            'total_patients': 1,
            'active_patients': 1,
            'recent_visits': 0,
            'avg_age': 39
        },
        'demographics': {
            'gender_distribution': {
                'male': 1,
                'female': 0,
                'other': 0
            },
            'age_groups': {
                '0-17': 0,
                '18-64': 1,
                '65+': 0
            }
        }
    }
EOF
    
    # Create deployment packages
    cd "${SCRIPT_DIR}"
    zip -r lambda-processor.zip lambda-processor.py
    zip -r lambda-analytics.zip lambda-analytics.py
    
    # Create Lambda functions
    if ! aws lambda get-function --function-name "${LAMBDA_PROCESSOR_NAME}" &>/dev/null; then
        aws lambda create-function \
            --function-name "${LAMBDA_PROCESSOR_NAME}" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_EXECUTION_ROLE}" \
            --handler lambda-processor.lambda_handler \
            --zip-file "fileb://lambda-processor.zip" \
            --timeout 60 \
            --memory-size 256
        log_success "Created Lambda processor function"
    else
        log_warn "Lambda processor function already exists"
    fi
    
    if ! aws lambda get-function --function-name "${LAMBDA_ANALYTICS_NAME}" &>/dev/null; then
        aws lambda create-function \
            --function-name "${LAMBDA_ANALYTICS_NAME}" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_EXECUTION_ROLE}" \
            --handler lambda-analytics.lambda_handler \
            --zip-file "fileb://lambda-analytics.zip" \
            --timeout 60 \
            --memory-size 256 \
            --environment "Variables={OUTPUT_BUCKET=${OUTPUT_BUCKET}}"
        log_success "Created Lambda analytics function"
    else
        log_warn "Lambda analytics function already exists"
    fi
}

# Configure EventBridge rules
configure_eventbridge() {
    log_info "Configuring EventBridge rules..."
    
    # Create processor rule
    if ! aws events describe-rule --name "HealthLakeProcessorRule" &>/dev/null; then
        aws events put-rule \
            --name "HealthLakeProcessorRule" \
            --event-pattern '{
              "source": ["aws.healthlake"],
              "detail-type": [
                "HealthLake Import Job State Change",
                "HealthLake Export Job State Change",
                "HealthLake Data Store State Change"
              ]
            }'
        
        aws events put-targets \
            --rule "HealthLakeProcessorRule" \
            --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_PROCESSOR_NAME}"
        
        aws lambda add-permission \
            --function-name "${LAMBDA_PROCESSOR_NAME}" \
            --statement-id "EventBridgeInvoke" \
            --action "lambda:InvokeFunction" \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/HealthLakeProcessorRule" \
            2>/dev/null || true
        
        log_success "Created EventBridge processor rule"
    else
        log_warn "EventBridge processor rule already exists"
    fi
    
    # Create analytics rule
    if ! aws events describe-rule --name "HealthLakeAnalyticsRule" &>/dev/null; then
        aws events put-rule \
            --name "HealthLakeAnalyticsRule" \
            --event-pattern '{
              "source": ["aws.healthlake"],
              "detail-type": ["HealthLake Import Job State Change"],
              "detail": {
                "jobStatus": ["COMPLETED"]
              }
            }'
        
        aws events put-targets \
            --rule "HealthLakeAnalyticsRule" \
            --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_ANALYTICS_NAME}"
        
        aws lambda add-permission \
            --function-name "${LAMBDA_ANALYTICS_NAME}" \
            --statement-id "EventBridgeInvoke" \
            --action "lambda:InvokeFunction" \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/HealthLakeAnalyticsRule" \
            2>/dev/null || true
        
        log_success "Created EventBridge analytics rule"
    else
        log_warn "EventBridge analytics rule already exists"
    fi
}

# Import sample data
import_sample_data() {
    log_info "Starting FHIR data import..."
    
    # Start import job
    IMPORT_JOB_ID=$(aws healthlake start-fhir-import-job \
        --input-data-config "S3Uri=s3://${INPUT_BUCKET}/fhir-data/" \
        --output-data-config "S3Uri=s3://${OUTPUT_BUCKET}/import-logs/" \
        --datastore-id "${DATASTORE_ID}" \
        --data-access-role-arn "${HEALTHLAKE_ROLE_ARN}" \
        --query 'JobId' --output text)
    
    echo "IMPORT_JOB_ID=${IMPORT_JOB_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "FHIR import job started: ${IMPORT_JOB_ID}"
    log_info "Monitor import progress with: aws healthlake describe-fhir-import-job --datastore-id ${DATASTORE_ID} --job-id ${IMPORT_JOB_ID}"
}

# Cleanup function
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -f "${SCRIPT_DIR}"/healthlake-trust-policy.json
    rm -f "${SCRIPT_DIR}"/healthlake-s3-policy.json
    rm -f "${SCRIPT_DIR}"/lambda-trust-policy.json
    rm -f "${SCRIPT_DIR}"/lambda-s3-policy.json
    rm -f "${SCRIPT_DIR}"/lambda-processor.py
    rm -f "${SCRIPT_DIR}"/lambda-processor.zip
    rm -f "${SCRIPT_DIR}"/lambda-analytics.py
    rm -f "${SCRIPT_DIR}"/lambda-analytics.zip
    rm -f "${SCRIPT_DIR}"/patient-sample.json
}

# Main deployment function
main() {
    log_info "Starting Healthcare Data Processing Pipeline deployment..."
    log_info "Deployment log: ${LOG_FILE}"
    
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_sample_data
    create_healthlake_iam_role
    create_healthlake_datastore
    create_lambda_functions
    configure_eventbridge
    import_sample_data
    cleanup_temp_files
    
    log_success "Healthcare Data Processing Pipeline deployed successfully!"
    log_info "Resources created:"
    log_info "  - HealthLake Datastore: ${DATASTORE_NAME} (${DATASTORE_ID})"
    log_info "  - Input S3 Bucket: ${INPUT_BUCKET}"
    log_info "  - Output S3 Bucket: ${OUTPUT_BUCKET}"
    log_info "  - Lambda Processor: ${LAMBDA_PROCESSOR_NAME}"
    log_info "  - Lambda Analytics: ${LAMBDA_ANALYTICS_NAME}"
    log_info ""
    log_info "Next steps:"
    log_info "1. Monitor import job status: aws healthlake describe-fhir-import-job --datastore-id ${DATASTORE_ID} --job-id ${IMPORT_JOB_ID}"
    log_info "2. Query FHIR data: curl -X GET '${DATASTORE_ENDPOINT}Patient'"
    log_info "3. Check analytics reports in S3: aws s3 ls s3://${OUTPUT_BUCKET}/analytics/"
    log_info ""
    log_info "Environment variables saved to: ${SCRIPT_DIR}/.env"
    log_info "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"