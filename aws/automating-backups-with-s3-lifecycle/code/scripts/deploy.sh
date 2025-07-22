#!/bin/bash

# =============================================================================
# AWS S3 Scheduled Backups - Deployment Script
# =============================================================================
# This script deploys the complete AWS S3 scheduled backup solution including:
# - Primary and backup S3 buckets
# - Lambda function for backup processing
# - EventBridge rule for scheduling
# - IAM roles and policies
# =============================================================================

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not configured or not authenticated"
        error "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
}

# Function to check if bucket exists
bucket_exists() {
    aws s3api head-bucket --bucket "$1" >/dev/null 2>&1
}

# Function to check if IAM role exists
role_exists() {
    aws iam get-role --role-name "$1" >/dev/null 2>&1
}

# Function to check if Lambda function exists
lambda_exists() {
    aws lambda get-function --function-name "$1" >/dev/null 2>&1
}

# Function to check if EventBridge rule exists
rule_exists() {
    aws events describe-rule --name "$1" >/dev/null 2>&1
}

# Function to wait for IAM role to be available
wait_for_role() {
    local role_name="$1"
    local max_attempts=30
    local attempt=1
    
    log "Waiting for IAM role $role_name to be available..."
    
    while [ $attempt -le $max_attempts ]; do
        if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
            success "IAM role $role_name is available"
            return 0
        fi
        
        log "Attempt $attempt/$max_attempts: Waiting for role to be available..."
        sleep 2
        ((attempt++))
    done
    
    error "Timeout waiting for IAM role $role_name to be available"
    return 1
}

# Function to create directory if it doesn't exist
create_temp_dir() {
    local dir_name="s3-backup-deployment-$(date +%s)"
    mkdir -p "$dir_name"
    cd "$dir_name"
    echo "$dir_name"
}

# Function to cleanup on exit
cleanup() {
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        log "Cleaning up temporary files..."
        cd ..
        rm -rf "$TEMP_DIR"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# =============================================================================
# MAIN DEPLOYMENT SCRIPT
# =============================================================================

log "Starting AWS S3 Scheduled Backups deployment..."

# Check prerequisites
log "Checking prerequisites..."

if ! command_exists aws; then
    error "AWS CLI is not installed"
    error "Please install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

if ! command_exists python3; then
    error "Python 3 is not installed"
    error "Please install Python 3 to create the Lambda function"
    exit 1
fi

if ! command_exists zip; then
    error "zip utility is not installed"
    error "Please install zip utility to package the Lambda function"
    exit 1
fi

check_aws_auth

# Get AWS account and region information
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$AWS_REGION" ]; then
    error "AWS region not set"
    error "Please run 'aws configure' to set your default region"
    exit 1
fi

log "AWS Account ID: $AWS_ACCOUNT_ID"
log "AWS Region: $AWS_REGION"

# Generate unique identifiers
export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s)")

# Set resource names
export PRIMARY_BUCKET="primary-data-${RANDOM_SUFFIX}"
export BACKUP_BUCKET="backup-data-${RANDOM_SUFFIX}"
export LAMBDA_FUNCTION_NAME="s3-backup-function-${RANDOM_SUFFIX}"
export LAMBDA_ROLE_NAME="s3-backup-lambda-role-${RANDOM_SUFFIX}"
export EVENTBRIDGE_RULE_NAME="DailyS3BackupRule-${RANDOM_SUFFIX}"

log "Resource names:"
log "  Primary Bucket: $PRIMARY_BUCKET"
log "  Backup Bucket: $BACKUP_BUCKET"
log "  Lambda Function: $LAMBDA_FUNCTION_NAME"
log "  IAM Role: $LAMBDA_ROLE_NAME"
log "  EventBridge Rule: $EVENTBRIDGE_RULE_NAME"

# Create temporary directory for deployment files
TEMP_DIR=$(create_temp_dir)
log "Created temporary directory: $TEMP_DIR"

# =============================================================================
# STEP 1: Create S3 Buckets
# =============================================================================

log "Creating S3 buckets..."

# Create primary bucket
if bucket_exists "$PRIMARY_BUCKET"; then
    warning "Primary bucket $PRIMARY_BUCKET already exists, skipping creation"
else
    log "Creating primary bucket: $PRIMARY_BUCKET"
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$PRIMARY_BUCKET" --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$PRIMARY_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    success "Created primary bucket: $PRIMARY_BUCKET"
fi

# Create backup bucket
if bucket_exists "$BACKUP_BUCKET"; then
    warning "Backup bucket $BACKUP_BUCKET already exists, skipping creation"
else
    log "Creating backup bucket: $BACKUP_BUCKET"
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BACKUP_BUCKET" --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$BACKUP_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    success "Created backup bucket: $BACKUP_BUCKET"
fi

# =============================================================================
# STEP 2: Configure Backup Bucket
# =============================================================================

log "Configuring backup bucket..."

# Enable versioning on backup bucket
log "Enabling versioning on backup bucket..."
aws s3api put-bucket-versioning \
    --bucket "$BACKUP_BUCKET" \
    --versioning-configuration Status=Enabled
success "Enabled versioning on backup bucket"

# Create and apply lifecycle policy
log "Creating lifecycle policy for backup bucket..."
cat > lifecycle-policy.json << 'EOF'
{
  "Rules": [
    {
      "ID": "BackupRetentionRule",
      "Status": "Enabled",
      "Filter": {
        "Prefix": ""
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 365
      }
    }
  ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
    --bucket "$BACKUP_BUCKET" \
    --lifecycle-configuration file://lifecycle-policy.json
success "Applied lifecycle policy to backup bucket"

# =============================================================================
# STEP 3: Create IAM Role
# =============================================================================

log "Creating IAM role for Lambda function..."

if role_exists "$LAMBDA_ROLE_NAME"; then
    warning "IAM role $LAMBDA_ROLE_NAME already exists, skipping creation"
else
    # Create trust policy document
    cat > trust-policy.json << 'EOF'
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

    # Create the IAM role
    aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document file://trust-policy.json
    success "Created IAM role: $LAMBDA_ROLE_NAME"
fi

# Create policy document
log "Creating IAM policy for S3 access..."
cat > s3-permissions.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${PRIMARY_BUCKET}",
        "arn:aws:s3:::${PRIMARY_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BACKUP_BUCKET}",
        "arn:aws:s3:::${BACKUP_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
EOF

# Attach policy to role
aws iam put-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-name S3BackupPermissions \
    --policy-document file://s3-permissions.json
success "Attached S3 permissions policy to IAM role"

# Wait for role to be available
wait_for_role "$LAMBDA_ROLE_NAME"

# =============================================================================
# STEP 4: Create Lambda Function
# =============================================================================

log "Creating Lambda function..."

if lambda_exists "$LAMBDA_FUNCTION_NAME"; then
    warning "Lambda function $LAMBDA_FUNCTION_NAME already exists, updating code..."
    UPDATE_LAMBDA=true
else
    UPDATE_LAMBDA=false
fi

# Create Lambda function code
log "Creating Lambda function code..."
cat > lambda_function.py << 'EOF'
import boto3
import os
import time
import json
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    """
    Lambda function to backup objects from source S3 bucket to destination S3 bucket
    """
    
    # Get bucket names from environment variables
    source_bucket = os.environ.get('SOURCE_BUCKET')
    destination_bucket = os.environ.get('DESTINATION_BUCKET')
    
    if not source_bucket or not destination_bucket:
        error_msg = "SOURCE_BUCKET and DESTINATION_BUCKET environment variables must be set"
        print(error_msg)
        return {
            'statusCode': 400,
            'body': json.dumps({'error': error_msg})
        }
    
    # Initialize S3 client
    s3 = boto3.client('s3')
    
    # Get current timestamp for logging
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S UTC")
    print(f"Starting backup process at {timestamp}")
    print(f"Source bucket: {source_bucket}")
    print(f"Destination bucket: {destination_bucket}")
    
    try:
        # List objects in source bucket
        objects = []
        paginator = s3.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=source_bucket):
            if 'Contents' in page:
                objects.extend(page['Contents'])
        
        print(f"Found {len(objects)} objects in source bucket")
        
        # Copy each object to the destination bucket
        copied_count = 0
        errors = []
        
        for obj in objects:
            key = obj['Key']
            
            try:
                copy_source = {'Bucket': source_bucket, 'Key': key}
                
                print(f"Copying {key} to backup bucket")
                s3.copy_object(
                    CopySource=copy_source,
                    Bucket=destination_bucket,
                    Key=key
                )
                copied_count += 1
                
            except ClientError as e:
                error_msg = f"Failed to copy {key}: {str(e)}"
                print(error_msg)
                errors.append(error_msg)
        
        completion_timestamp = time.strftime("%Y-%m-%d %H:%M:%S UTC")
        print(f"Backup completed at {completion_timestamp}")
        print(f"Successfully copied {copied_count} objects")
        
        if errors:
            print(f"Encountered {len(errors)} errors:")
            for error in errors:
                print(f"  - {error}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Backup completed successfully',
                'copied_objects': copied_count,
                'total_objects': len(objects),
                'errors': len(errors),
                'timestamp': completion_timestamp
            })
        }
        
    except ClientError as e:
        error_msg = f"Failed to list objects in source bucket: {str(e)}"
        print(error_msg)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': error_msg})
        }
    
    except Exception as e:
        error_msg = f"Unexpected error: {str(e)}"
        print(error_msg)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': error_msg})
        }
EOF

# Package the Lambda function
log "Packaging Lambda function..."
zip -q lambda_function.zip lambda_function.py
success "Packaged Lambda function"

if [ "$UPDATE_LAMBDA" = true ]; then
    # Update existing Lambda function
    log "Updating existing Lambda function code..."
    aws lambda update-function-code \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --zip-file fileb://lambda_function.zip
    
    # Update environment variables
    aws lambda update-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --environment "Variables={SOURCE_BUCKET=${PRIMARY_BUCKET},DESTINATION_BUCKET=${BACKUP_BUCKET}}"
    
    success "Updated Lambda function: $LAMBDA_FUNCTION_NAME"
else
    # Create new Lambda function
    log "Creating new Lambda function..."
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --handler lambda_function.lambda_handler \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
        --zip-file fileb://lambda_function.zip \
        --environment "Variables={SOURCE_BUCKET=${PRIMARY_BUCKET},DESTINATION_BUCKET=${BACKUP_BUCKET}}" \
        --timeout 300 \
        --memory-size 256 \
        --description "Automated S3 backup function"
    
    success "Created Lambda function: $LAMBDA_FUNCTION_NAME"
fi

# =============================================================================
# STEP 5: Create EventBridge Rule
# =============================================================================

log "Creating EventBridge rule for scheduled backups..."

if rule_exists "$EVENTBRIDGE_RULE_NAME"; then
    warning "EventBridge rule $EVENTBRIDGE_RULE_NAME already exists, updating..."
else
    # Create EventBridge rule
    aws events put-rule \
        --name "$EVENTBRIDGE_RULE_NAME" \
        --schedule-expression "cron(0 1 * * ? *)" \
        --description "Trigger S3 backup function daily at 1:00 AM UTC" \
        --state ENABLED
    success "Created EventBridge rule: $EVENTBRIDGE_RULE_NAME"
fi

# Add permission for EventBridge to invoke Lambda function
log "Adding EventBridge permission to Lambda function..."
aws lambda add-permission \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --statement-id "EventBridgeInvoke-${RANDOM_SUFFIX}" \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}" \
    2>/dev/null || warning "Permission may already exist"

# Create target for the rule
log "Adding Lambda function as target for EventBridge rule..."
aws events put-targets \
    --rule "$EVENTBRIDGE_RULE_NAME" \
    --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
success "Added Lambda function as target for EventBridge rule"

# =============================================================================
# STEP 6: Upload Sample Data and Test
# =============================================================================

log "Uploading sample data to primary bucket..."

# Create sample files
echo "This is sample file 1 - created on $(date)" > sample-file-1.txt
echo "This is sample file 2 - created on $(date)" > sample-file-2.txt
echo "This is sample file 3 - created on $(date)" > sample-file-3.txt

# Upload files to primary bucket
aws s3 cp sample-file-1.txt "s3://${PRIMARY_BUCKET}/"
aws s3 cp sample-file-2.txt "s3://${PRIMARY_BUCKET}/"
aws s3 cp sample-file-3.txt "s3://${PRIMARY_BUCKET}/"
success "Uploaded sample files to primary bucket"

# Test the backup function
log "Testing backup function manually..."
aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --payload '{}' \
    --cli-binary-format raw-in-base64-out \
    response.json >/dev/null

# Check response
if [ -f response.json ]; then
    if grep -q '"statusCode": 200' response.json; then
        success "Backup function test completed successfully"
        log "Response: $(cat response.json)"
    else
        warning "Backup function test may have encountered issues"
        log "Response: $(cat response.json)"
    fi
else
    warning "Could not retrieve test response"
fi

# =============================================================================
# DEPLOYMENT COMPLETE
# =============================================================================

success "AWS S3 Scheduled Backups deployment completed successfully!"

echo ""
echo "============================================================================="
echo "DEPLOYMENT SUMMARY"
echo "============================================================================="
echo "✅ Primary S3 Bucket: $PRIMARY_BUCKET"
echo "✅ Backup S3 Bucket: $BACKUP_BUCKET (versioning enabled)"
echo "✅ Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "✅ IAM Role: $LAMBDA_ROLE_NAME"
echo "✅ EventBridge Rule: $EVENTBRIDGE_RULE_NAME (daily at 1:00 AM UTC)"
echo ""
echo "BACKUP SCHEDULE:"
echo "  • Daily backup at 1:00 AM UTC"
echo "  • Lifecycle policy: Standard → Standard-IA (30 days) → Glacier (90 days) → Expire (365 days)"
echo ""
echo "VERIFICATION:"
echo "  • Sample files uploaded to primary bucket"
echo "  • Backup function tested successfully"
echo "  • Check backup bucket: aws s3 ls s3://$BACKUP_BUCKET/"
echo ""
echo "NEXT STEPS:"
echo "  • Upload your data to the primary bucket: s3://$PRIMARY_BUCKET/"
echo "  • Monitor backup operations in CloudWatch logs"
echo "  • Customize backup schedule if needed (modify EventBridge rule)"
echo ""
echo "CLEANUP:"
echo "  • Run './destroy.sh' to remove all resources"
echo "============================================================================="

# Save deployment information
cat > deployment-info.txt << EOF
# AWS S3 Scheduled Backups Deployment Information
# Generated on: $(date)

export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export PRIMARY_BUCKET="$PRIMARY_BUCKET"
export BACKUP_BUCKET="$BACKUP_BUCKET"
export LAMBDA_FUNCTION_NAME="$LAMBDA_FUNCTION_NAME"
export LAMBDA_ROLE_NAME="$LAMBDA_ROLE_NAME"
export EVENTBRIDGE_RULE_NAME="$EVENTBRIDGE_RULE_NAME"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF

success "Deployment information saved to deployment-info.txt"
log "Deployment completed at $(date)"