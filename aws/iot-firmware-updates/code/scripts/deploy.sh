#!/bin/bash

# AWS IoT Firmware Updates with Device Management Jobs - Deployment Script
# This script deploys the complete infrastructure for IoT firmware updates
# including IoT Things, Lambda functions, S3 storage, and AWS Signer profiles

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

# Progress tracking
show_progress() {
    echo -e "${BLUE}[PROGRESS]${NC} $1..."
}

# Check if AWS CLI is installed and configured
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    local required_tools=("python3" "zip" "wc" "sha256sum")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' is not installed."
            exit 1
        fi
    done
    
    # Check AWS permissions by testing a simple command
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity &> /dev/null; then
        log_error "Insufficient AWS permissions. Please ensure you have IoT, Lambda, S3, IAM, and Signer permissions."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Export resource names
    export FIRMWARE_BUCKET="firmware-updates-${RANDOM_SUFFIX}"
    export THING_NAME="iot-device-${RANDOM_SUFFIX}"
    export THING_GROUP="firmware-update-group-${RANDOM_SUFFIX}"
    export JOB_ROLE_NAME="IoTJobsRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="FirmwareUpdateLambdaRole-${RANDOM_SUFFIX}"
    export SIGNING_PROFILE_NAME="firmware-signing-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
FIRMWARE_BUCKET=${FIRMWARE_BUCKET}
THING_NAME=${THING_NAME}
THING_GROUP=${THING_GROUP}
JOB_ROLE_NAME=${JOB_ROLE_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
SIGNING_PROFILE_NAME=${SIGNING_PROFILE_NAME}
EOF
    
    log_success "Environment variables configured"
    log_info "Resources will be created with suffix: ${RANDOM_SUFFIX}"
}

# Create S3 bucket for firmware storage
create_s3_bucket() {
    show_progress "Creating S3 bucket for firmware storage"
    
    # Check if bucket already exists
    if aws s3 ls "s3://${FIRMWARE_BUCKET}" &> /dev/null; then
        log_warning "S3 bucket ${FIRMWARE_BUCKET} already exists"
        return 0
    fi
    
    # Create bucket with appropriate region handling
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${FIRMWARE_BUCKET}"
    else
        aws s3 mb "s3://${FIRMWARE_BUCKET}" --region "${AWS_REGION}"
    fi
    
    # Enable versioning for better firmware management
    aws s3api put-bucket-versioning \
        --bucket "${FIRMWARE_BUCKET}" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "${FIRMWARE_BUCKET}" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    log_success "S3 bucket created: ${FIRMWARE_BUCKET}"
}

# Create IoT Thing and Thing Group
create_iot_resources() {
    show_progress "Creating IoT Thing and Thing Group"
    
    # Create IoT Thing
    if ! aws iot describe-thing --thing-name "${THING_NAME}" &> /dev/null; then
        aws iot create-thing --thing-name "${THING_NAME}"
        log_success "IoT Thing created: ${THING_NAME}"
    else
        log_warning "IoT Thing ${THING_NAME} already exists"
    fi
    
    # Create Thing Group
    if ! aws iot describe-thing-group --thing-group-name "${THING_GROUP}" &> /dev/null; then
        aws iot create-thing-group \
            --thing-group-name "${THING_GROUP}" \
            --thing-group-properties "thingGroupDescription=\"Devices for firmware updates - deployed $(date)\""
        log_success "Thing Group created: ${THING_GROUP}"
        
        # Add thing to group
        aws iot add-thing-to-thing-group \
            --thing-group-name "${THING_GROUP}" \
            --thing-name "${THING_NAME}"
        log_success "Thing added to group"
    else
        log_warning "Thing Group ${THING_GROUP} already exists"
    fi
}

# Create IAM role for IoT Jobs
create_iot_jobs_role() {
    show_progress "Creating IAM role for IoT Jobs"
    
    # Check if role already exists
    if aws iam get-role --role-name "${JOB_ROLE_NAME}" &> /dev/null; then
        log_warning "IAM role ${JOB_ROLE_NAME} already exists"
        export JOB_ROLE_ARN=$(aws iam get-role --role-name "${JOB_ROLE_NAME}" --query Role.Arn --output text)
        return 0
    fi
    
    # Create trust policy for IoT Jobs
    cat > iot-jobs-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "iot.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create the role
    aws iam create-role \
        --role-name "${JOB_ROLE_NAME}" \
        --assume-role-policy-document file://iot-jobs-trust-policy.json \
        --description "IAM role for IoT Jobs to access S3 firmware storage"
    
    # Create permission policy for S3 access
    cat > iot-jobs-permission-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::${FIRMWARE_BUCKET}/*"
    }
  ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "${JOB_ROLE_NAME}" \
        --policy-name IoTJobsS3Access \
        --policy-document file://iot-jobs-permission-policy.json
    
    export JOB_ROLE_ARN=$(aws iam get-role \
        --role-name "${JOB_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    # Save to environment file
    echo "JOB_ROLE_ARN=${JOB_ROLE_ARN}" >> .env
    
    log_success "IoT Jobs role created: ${JOB_ROLE_ARN}"
}

# Create AWS Signer profile
create_signer_profile() {
    show_progress "Creating AWS Signer profile for code signing"
    
    # Check if profile already exists
    if aws signer describe-signing-job --job-id "dummy" &> /dev/null; then
        # This is just to test signer permissions, the error is expected
        :
    fi
    
    # Create signing profile
    if ! aws signer get-signing-profile --profile-name "${SIGNING_PROFILE_NAME}" &> /dev/null; then
        aws signer put-signing-profile \
            --profile-name "${SIGNING_PROFILE_NAME}" \
            --platform-id "AmazonFreeRTOS-TI-CC3220SF" \
            --signature-validity-period "value=365,type=Days"
        
        log_success "Signing profile created: ${SIGNING_PROFILE_NAME}"
    else
        log_warning "Signing profile ${SIGNING_PROFILE_NAME} already exists"
    fi
}

# Create Lambda execution role
create_lambda_role() {
    show_progress "Creating IAM role for Lambda function"
    
    # Check if role already exists
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
        log_warning "Lambda role ${LAMBDA_ROLE_NAME} already exists"
        export LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" --query Role.Arn --output text)
        return 0
    fi
    
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
    
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --description "IAM role for firmware update Lambda function"
    
    # Attach managed policy for basic Lambda execution
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for IoT and S3 access
    cat > lambda-permission-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:CreateJob",
        "iot:DescribeJob",
        "iot:ListJobs",
        "iot:UpdateJob",
        "iot:CancelJob",
        "iot:DeleteJob",
        "iot:ListJobExecutionsForJob",
        "iot:ListJobExecutionsForThing",
        "iot:DescribeJobExecution"
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
        "arn:aws:s3:::${FIRMWARE_BUCKET}",
        "arn:aws:s3:::${FIRMWARE_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "signer:StartSigningJob",
        "signer:DescribeSigningJob",
        "signer:ListSigningJobs"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-name FirmwareUpdatePermissions \
        --policy-document file://lambda-permission-policy.json
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    # Save to environment file
    echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> .env
    
    log_success "Lambda role created: ${LAMBDA_ROLE_ARN}"
}

# Create Lambda function
create_lambda_function() {
    show_progress "Creating Lambda function for firmware update management"
    
    # Check if function already exists
    if aws lambda get-function --function-name firmware-update-manager &> /dev/null; then
        log_warning "Lambda function firmware-update-manager already exists"
        return 0
    fi
    
    # Create Lambda function code
    cat > firmware_update_manager.py << 'EOF'
import json
import boto3
import uuid
from datetime import datetime, timedelta

def lambda_handler(event, context):
    iot_client = boto3.client('iot')
    s3_client = boto3.client('s3')
    signer_client = boto3.client('signer')
    
    action = event.get('action')
    
    if action == 'create_job':
        return create_firmware_job(event, iot_client, s3_client)
    elif action == 'check_job_status':
        return check_job_status(event, iot_client)
    elif action == 'cancel_job':
        return cancel_job(event, iot_client)
    else:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid action'})
        }

def create_firmware_job(event, iot_client, s3_client):
    try:
        firmware_version = event['firmware_version']
        thing_group = event['thing_group']
        s3_bucket = event['s3_bucket']
        s3_key = event['s3_key']
        
        # Create job document
        job_document = {
            "operation": "firmware_update",
            "firmware": {
                "version": firmware_version,
                "url": f"https://{s3_bucket}.s3.amazonaws.com/{s3_key}",
                "size": get_object_size(s3_client, s3_bucket, s3_key),
                "checksum": get_object_checksum(s3_client, s3_bucket, s3_key)
            },
            "steps": [
                "download_firmware",
                "verify_signature",
                "backup_current_firmware",
                "install_firmware",
                "verify_installation",
                "report_status"
            ]
        }
        
        # Create unique job ID
        job_id = f"firmware-update-{firmware_version}-{uuid.uuid4().hex[:8]}"
        
        # Create the job
        response = iot_client.create_job(
            jobId=job_id,
            targets=[f"arn:aws:iot:{boto3.Session().region_name}:{boto3.client('sts').get_caller_identity()['Account']}:thinggroup/{thing_group}"],
            document=json.dumps(job_document),
            description=f"Firmware update to version {firmware_version}",
            targetSelection='SNAPSHOT',
            jobExecutionsRolloutConfig={
                'maximumPerMinute': 10,
                'exponentialRate': {
                    'baseRatePerMinute': 5,
                    'incrementFactor': 2.0,
                    'rateIncreaseCriteria': {
                        'numberOfNotifiedThings': 10,
                        'numberOfSucceededThings': 5
                    }
                }
            },
            abortConfig={
                'criteriaList': [
                    {
                        'failureType': 'FAILED',
                        'action': 'CANCEL',
                        'thresholdPercentage': 20.0,
                        'minNumberOfExecutedThings': 5
                    }
                ]
            },
            timeoutConfig={
                'inProgressTimeoutInMinutes': 60
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'job_id': job_id,
                'job_arn': response['jobArn'],
                'message': 'Firmware update job created successfully'
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def check_job_status(event, iot_client):
    try:
        job_id = event['job_id']
        
        response = iot_client.describe_job(jobId=job_id)
        job_executions = iot_client.list_job_executions_for_job(jobId=job_id)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'job_id': job_id,
                'status': response['job']['status'],
                'process_details': response['job']['jobProcessDetails'],
                'executions': job_executions['executionSummaries']
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def cancel_job(event, iot_client):
    try:
        job_id = event['job_id']
        
        iot_client.cancel_job(
            jobId=job_id,
            reasonCode='USER_INITIATED',
            comment='Job cancelled by user'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'job_id': job_id,
                'message': 'Job cancelled successfully'
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_object_size(s3_client, bucket, key):
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response['ContentLength']
    except:
        return 0

def get_object_checksum(s3_client, bucket, key):
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response.get('ETag', '').replace('"', '')
    except:
        return ''
EOF
    
    # Create deployment package
    zip -q firmware_update_manager.zip firmware_update_manager.py
    
    # Wait for IAM role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    # Create Lambda function
    aws lambda create-function \
        --function-name firmware-update-manager \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler firmware_update_manager.lambda_handler \
        --zip-file fileb://firmware_update_manager.zip \
        --timeout 300 \
        --memory-size 256 \
        --description "Manages IoT firmware update jobs" \
        --tags "Project=IoTFirmwareUpdates,Environment=Demo"
    
    log_success "Lambda function created: firmware-update-manager"
}

# Create sample firmware and upload to S3
create_sample_firmware() {
    show_progress "Creating and uploading sample firmware"
    
    # Create sample firmware file
    cat > sample_firmware_v1.0.0.bin << 'EOF'
# Sample Firmware v1.0.0
# This is a simulated firmware binary for testing
# In production, this would be your actual firmware image

FIRMWARE_VERSION=1.0.0
FIRMWARE_BUILD=20241211
FIRMWARE_FEATURES=["ota_support", "security_patch", "bug_fixes"]

# Simulated binary data
BINARY_DATA_START
00000000: 7f45 4c46 0101 0100 0000 0000 0000 0000  .ELF............
00000010: 0200 0300 0100 0000 8080 0408 3400 0000  ............4...
00000020: 0000 0000 0000 0000 3400 2000 0100 0000  ........4. .....
BINARY_DATA_END
EOF
    
    # Upload firmware to S3
    aws s3 cp sample_firmware_v1.0.0.bin \
        "s3://${FIRMWARE_BUCKET}/firmware/sample_firmware_v1.0.0.bin"
    
    # Create firmware metadata
    local firmware_size=$(wc -c < sample_firmware_v1.0.0.bin)
    local firmware_checksum=$(sha256sum sample_firmware_v1.0.0.bin | cut -d' ' -f1)
    
    cat > firmware_metadata.json << EOF
{
  "version": "1.0.0",
  "build": "20241211",
  "description": "Sample firmware with OTA support and security patches",
  "features": ["ota_support", "security_patch", "bug_fixes"],
  "size": ${firmware_size},
  "checksum": "${firmware_checksum}",
  "upload_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    aws s3 cp firmware_metadata.json \
        "s3://${FIRMWARE_BUCKET}/firmware/sample_firmware_v1.0.0.json"
    
    log_success "Sample firmware uploaded to S3"
}

# Sign the firmware
sign_firmware() {
    show_progress "Signing firmware with AWS Signer"
    
    # Start signing job for the firmware
    local signing_job_id
    signing_job_id=$(aws signer start-signing-job \
        --source "s3={bucketName=${FIRMWARE_BUCKET},key=firmware/sample_firmware_v1.0.0.bin,version=null}" \
        --destination "s3={bucketName=${FIRMWARE_BUCKET},prefix=signed-firmware/}" \
        --profile-name "${SIGNING_PROFILE_NAME}" \
        --query 'jobId' --output text)
    
    log_info "Signing job started: ${signing_job_id}"
    
    # Wait for signing to complete
    log_info "Waiting for firmware signing to complete..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local signing_status
        signing_status=$(aws signer describe-signing-job \
            --job-id "${signing_job_id}" \
            --query 'status' --output text)
        
        if [ "$signing_status" = "Succeeded" ]; then
            log_success "Firmware signing completed successfully"
            break
        elif [ "$signing_status" = "Failed" ]; then
            log_error "Firmware signing failed"
            aws signer describe-signing-job --job-id "${signing_job_id}"
            return 1
        else
            log_info "Signing status: ${signing_status} (attempt $((attempt + 1))/${max_attempts})"
            sleep 10
            ((attempt++))
        fi
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_error "Firmware signing timed out"
        return 1
    fi
    
    # Get signed firmware location
    export SIGNED_FIRMWARE_KEY=$(aws signer describe-signing-job \
        --job-id "${signing_job_id}" \
        --query 'signedObject.s3.key' --output text)
    
    # Save to environment file
    echo "SIGNED_FIRMWARE_KEY=${SIGNED_FIRMWARE_KEY}" >> .env
    echo "SIGNING_JOB_ID=${signing_job_id}" >> .env
    
    log_success "Signed firmware available at: s3://${FIRMWARE_BUCKET}/${SIGNED_FIRMWARE_KEY}"
}

# Create CloudWatch dashboard
create_cloudwatch_dashboard() {
    show_progress "Creating CloudWatch dashboard for monitoring"
    
    # Create dashboard configuration
    cat > iot_jobs_dashboard.json << EOF
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
          ["AWS/IoT", "JobsCompleted"],
          [".", "JobsFailed"],
          [".", "JobsInProgress"],
          [".", "JobsQueued"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "IoT Jobs Status"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 6,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE '/aws/lambda/firmware-update-manager' | fields @timestamp, @message | sort @timestamp desc | limit 100",
        "region": "${AWS_REGION}",
        "title": "Firmware Update Manager Logs"
      }
    }
  ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "IoT-Firmware-Updates" \
        --dashboard-body file://iot_jobs_dashboard.json
    
    log_success "CloudWatch dashboard created: IoT-Firmware-Updates"
}

# Create device simulator
create_device_simulator() {
    show_progress "Creating device simulator for testing"
    
    cat > device_simulator.py << 'EOF'
import json
import boto3
import time
import random
from datetime import datetime

class IoTDeviceSimulator:
    def __init__(self, thing_name, region_name):
        self.thing_name = thing_name
        self.iot_data = boto3.client('iot-data', region_name=region_name)
        self.iot = boto3.client('iot', region_name=region_name)
        
    def start_job_listener(self):
        """Simulate device listening for job notifications"""
        print(f"Device {self.thing_name} listening for jobs...")
        
        try:
            # Get next pending job
            response = self.iot_data.get_pending_job_executions(
                thingName=self.thing_name
            )
            
            if response['inProgressJobs'] or response['queuedJobs']:
                jobs = response['inProgressJobs'] + response['queuedJobs']
                for job in jobs:
                    self.process_job(job)
            else:
                print("No pending jobs found")
                
        except Exception as e:
            print(f"Error getting pending jobs: {e}")
    
    def process_job(self, job):
        """Process a firmware update job"""
        job_id = job['jobId']
        print(f"Processing job: {job_id}")
        
        try:
            # Start job execution
            self.iot_data.start_next_pending_job_execution(
                thingName=self.thing_name,
                statusDetails={'step': 'starting', 'progress': '0%'}
            )
            
            # Simulate firmware update steps
            steps = [
                ('download_firmware', 'Downloading firmware', 20),
                ('verify_signature', 'Verifying signature', 40),
                ('backup_current_firmware', 'Backing up current firmware', 60),
                ('install_firmware', 'Installing firmware', 80),
                ('verify_installation', 'Verifying installation', 90),
                ('report_status', 'Reporting final status', 100)
            ]
            
            for step, description, progress in steps:
                print(f"  {description}... ({progress}%)")
                
                # Simulate processing time
                time.sleep(random.uniform(1, 3))
                
                # Update job status
                self.iot_data.update_job_execution(
                    jobId=job_id,
                    thingName=self.thing_name,
                    status='IN_PROGRESS',
                    statusDetails={
                        'step': step,
                        'progress': f'{progress}%',
                        'timestamp': datetime.utcnow().isoformat()
                    }
                )
            
            # Complete the job
            self.iot_data.update_job_execution(
                jobId=job_id,
                thingName=self.thing_name,
                status='SUCCEEDED',
                statusDetails={
                    'step': 'completed',
                    'progress': '100%',
                    'firmware_version': '1.0.0',
                    'completion_time': datetime.utcnow().isoformat()
                }
            )
            
            print(f"  ✅ Job {job_id} completed successfully")
            
        except Exception as e:
            print(f"  ❌ Job {job_id} failed: {e}")
            
            # Mark job as failed
            self.iot_data.update_job_execution(
                jobId=job_id,
                thingName=self.thing_name,
                status='FAILED',
                statusDetails={
                    'error': str(e),
                    'timestamp': datetime.utcnow().isoformat()
                }
            )

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3:
        print("Usage: python device_simulator.py <thing_name> <region>")
        sys.exit(1)
        
    thing_name = sys.argv[1]
    region = sys.argv[2]
    
    simulator = IoTDeviceSimulator(thing_name, region)
    simulator.start_job_listener()
EOF
    
    log_success "Device simulator created: device_simulator.py"
}

# Test the deployment
test_deployment() {
    show_progress "Testing the deployment"
    
    log_info "Running basic connectivity tests..."
    
    # Test S3 bucket access
    if aws s3 ls "s3://${FIRMWARE_BUCKET}/" > /dev/null; then
        log_success "S3 bucket accessible"
    else
        log_error "S3 bucket access failed"
        return 1
    fi
    
    # Test Lambda function
    if aws lambda get-function --function-name firmware-update-manager > /dev/null; then
        log_success "Lambda function accessible"
    else
        log_error "Lambda function access failed"
        return 1
    fi
    
    # Test IoT Thing
    if aws iot describe-thing --thing-name "${THING_NAME}" > /dev/null; then
        log_success "IoT Thing accessible"
    else
        log_error "IoT Thing access failed"
        return 1
    fi
    
    log_success "All basic tests passed"
}

# Display deployment summary
show_deployment_summary() {
    log_success "🎉 IoT Firmware Update infrastructure deployed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "AWS Region: ${AWS_REGION}"
    echo "S3 Bucket: ${FIRMWARE_BUCKET}"
    echo "IoT Thing: ${THING_NAME}"
    echo "Thing Group: ${THING_GROUP}"
    echo "Lambda Function: firmware-update-manager"
    echo "CloudWatch Dashboard: IoT-Firmware-Updates"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. View CloudWatch dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=IoT-Firmware-Updates"
    echo "2. Test firmware update job creation using the Lambda function"
    echo "3. Run device simulator: python3 device_simulator.py ${THING_NAME} ${AWS_REGION}"
    echo "4. When done testing, run: ./destroy.sh"
    echo
    echo "Environment variables saved to .env file for cleanup script"
    echo
    log_warning "Remember to run ./destroy.sh when finished to avoid ongoing charges"
}

# Main deployment function
main() {
    echo "🚀 Starting AWS IoT Firmware Updates deployment..."
    echo
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iot_resources
    create_iot_jobs_role
    create_signer_profile
    create_lambda_role
    create_lambda_function
    create_sample_firmware
    sign_firmware
    create_cloudwatch_dashboard
    create_device_simulator
    test_deployment
    show_deployment_summary
    
    echo
    log_success "Deployment completed successfully! 🎉"
    exit 0
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Some resources may have been created."
    log_info "Run ./destroy.sh to clean up any created resources."
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Run main function
main "$@"