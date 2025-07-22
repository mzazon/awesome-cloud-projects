#!/bin/bash

# Enterprise KMS Envelope Encryption with Key Rotation - Deployment Script
# Recipe: enterprise-kms-envelope-encryption-key-rotation
# Version: 1.0
# Description: Deploys enterprise KMS envelope encryption infrastructure with automated key rotation

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly TEMP_DIR=$(mktemp -d)

# Cleanup function for temporary files
cleanup() {
    local exit_code=$?
    echo -e "\n${BLUE}[INFO]${NC} Cleaning up temporary files..."
    rm -rf "${TEMP_DIR}"
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Deployment failed. Check ${LOG_FILE} for details."
    fi
    exit $exit_code
}

trap cleanup EXIT

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate AWS CLI and authentication
validate_aws_prerequisites() {
    print_status "$BLUE" "[INFO] Validating AWS prerequisites..."
    
    if ! command_exists aws; then
        print_status "$RED" "[ERROR] AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "INFO" "AWS CLI Version: $aws_version"
    
    # Test AWS authentication
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_status "$RED" "[ERROR] AWS CLI is not configured or lacks permissions"
        print_status "$YELLOW" "[HINT] Run 'aws configure' to set up your credentials"
        exit 1
    fi
    
    local caller_identity
    caller_identity=$(aws sts get-caller-identity --output json)
    local account_id=$(echo "$caller_identity" | jq -r '.Account')
    local user_arn=$(echo "$caller_identity" | jq -r '.Arn')
    
    log "INFO" "AWS Account ID: $account_id"
    log "INFO" "AWS User/Role: $user_arn"
    
    print_status "$GREEN" "✅ AWS prerequisites validated"
}

# Check required permissions
validate_permissions() {
    print_status "$BLUE" "[INFO] Validating AWS permissions..."
    
    local required_permissions=(
        "kms:CreateKey"
        "kms:CreateAlias"
        "kms:DescribeKey"
        "kms:EnableKeyRotation"
        "s3:CreateBucket"
        "s3:PutBucketEncryption"
        "s3:PutBucketVersioning"
        "lambda:CreateFunction"
        "iam:CreateRole"
        "iam:CreatePolicy"
        "events:PutRule"
        "events:PutTargets"
    )
    
    # Note: This is a simplified check. In production, you might want more thorough permission validation
    print_status "$YELLOW" "[INFO] Permission validation would require testing actual API calls"
    print_status "$YELLOW" "[INFO] Proceeding with deployment - errors will indicate missing permissions"
}

# Set environment variables
setup_environment() {
    print_status "$BLUE" "[INFO] Setting up environment variables..."
    
    # Check if AWS region is configured
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        print_status "$RED" "[ERROR] AWS region not configured"
        print_status "$YELLOW" "[HINT] Set AWS_REGION environment variable or configure default region"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export KMS_KEY_ALIAS="enterprise-encryption-${random_suffix}"
    export S3_BUCKET_NAME="enterprise-encrypted-data-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="kms-key-rotator-${random_suffix}"
    
    log "INFO" "Environment variables configured:"
    log "INFO" "  AWS_REGION: $AWS_REGION"
    log "INFO" "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log "INFO" "  KMS_KEY_ALIAS: $KMS_KEY_ALIAS"
    log "INFO" "  S3_BUCKET_NAME: $S3_BUCKET_NAME"
    log "INFO" "  LAMBDA_FUNCTION_NAME: $LAMBDA_FUNCTION_NAME"
    
    # Save environment to file for cleanup script
    cat > "${SCRIPT_DIR}/.deployment_env" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
KMS_KEY_ALIAS=$KMS_KEY_ALIAS
S3_BUCKET_NAME=$S3_BUCKET_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
EOF
    
    print_status "$GREEN" "✅ Environment variables configured"
}

# Create KMS Customer Master Key
create_kms_key() {
    print_status "$BLUE" "[INFO] Creating KMS Customer Master Key..."
    
    local cmk_id
    cmk_id=$(aws kms create-key \
        --description "Enterprise envelope encryption master key" \
        --key-usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --enable-key-rotation \
        --query KeyMetadata.KeyId --output text)
    
    if [[ -z "$cmk_id" ]]; then
        print_status "$RED" "[ERROR] Failed to create KMS key"
        exit 1
    fi
    
    # Create alias for the key
    aws kms create-alias \
        --alias-name "alias/${KMS_KEY_ALIAS}" \
        --target-key-id "$cmk_id"
    
    log "INFO" "KMS Key created with ID: $cmk_id"
    log "INFO" "KMS Key alias: alias/$KMS_KEY_ALIAS"
    
    # Store CMK ID for later use
    echo "$cmk_id" > "${SCRIPT_DIR}/.cmk_id"
    
    print_status "$GREEN" "✅ KMS Customer Master Key created successfully"
}

# Create S3 bucket with encryption
create_s3_bucket() {
    print_status "$BLUE" "[INFO] Creating S3 bucket with KMS encryption..."
    
    # Create S3 bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://${S3_BUCKET_NAME}"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Configure bucket encryption with KMS
    aws s3api put-bucket-encryption \
        --bucket "$S3_BUCKET_NAME" \
        --server-side-encryption-configuration "{
            \"Rules\": [{
                \"ApplyServerSideEncryptionByDefault\": {
                    \"SSEAlgorithm\": \"aws:kms\",
                    \"KMSMasterKeyID\": \"alias/${KMS_KEY_ALIAS}\"
                },
                \"BucketKeyEnabled\": true
            }]
        }"
    
    log "INFO" "S3 bucket created: $S3_BUCKET_NAME"
    log "INFO" "Bucket encryption configured with KMS key: alias/$KMS_KEY_ALIAS"
    
    print_status "$GREEN" "✅ S3 bucket created with KMS encryption"
}

# Create IAM role and policies for Lambda
create_iam_resources() {
    print_status "$BLUE" "[INFO] Creating IAM role and policies for Lambda function..."
    
    # Create trust policy for Lambda
    cat > "${TEMP_DIR}/lambda-trust-policy.json" << 'EOF'
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
    
    # Create IAM role for Lambda function
    aws iam create-role \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --assume-role-policy-document "file://${TEMP_DIR}/lambda-trust-policy.json"
    
    # Attach basic Lambda execution permissions
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom KMS policy
    cat > "${TEMP_DIR}/kms-management-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kms:DescribeKey",
                "kms:GetKeyRotationStatus",
                "kms:EnableKeyRotation",
                "kms:ListKeys",
                "kms:ListAliases"
            ],
            "Resource": "*"
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
    
    # Create and attach custom policy
    aws iam create-policy \
        --policy-name "${LAMBDA_FUNCTION_NAME}-kms-policy" \
        --policy-document "file://${TEMP_DIR}/kms-management-policy.json"
    
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-kms-policy"
    
    log "INFO" "IAM role created: ${LAMBDA_FUNCTION_NAME}-role"
    log "INFO" "IAM policy created: ${LAMBDA_FUNCTION_NAME}-kms-policy"
    
    print_status "$GREEN" "✅ IAM resources created successfully"
}

# Create Lambda function
create_lambda_function() {
    print_status "$BLUE" "[INFO] Creating Lambda function for key rotation monitoring..."
    
    # Create Lambda function code
    cat > "${TEMP_DIR}/key_rotation_monitor.py" << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    kms_client = boto3.client('kms')
    
    try:
        # List all customer-managed keys
        paginator = kms_client.get_paginator('list_keys')
        
        rotation_status = []
        
        for page in paginator.paginate():
            for key in page['Keys']:
                key_id = key['KeyId']
                
                # Get key details
                key_details = kms_client.describe_key(KeyId=key_id)
                
                # Skip AWS-managed keys
                if key_details['KeyMetadata']['KeyManager'] == 'AWS':
                    continue
                
                # Check rotation status
                rotation_enabled = kms_client.get_key_rotation_status(
                    KeyId=key_id
                )['KeyRotationEnabled']
                
                key_info = {
                    'KeyId': key_id,
                    'KeyArn': key_details['KeyMetadata']['Arn'],
                    'RotationEnabled': rotation_enabled,
                    'KeyState': key_details['KeyMetadata']['KeyState'],
                    'CreationDate': key_details['KeyMetadata']['CreationDate'].isoformat()
                }
                
                rotation_status.append(key_info)
                
                # Log key rotation status
                logger.info(f"Key {key_id}: Rotation {'enabled' if rotation_enabled else 'disabled'}")
                
                # Enable rotation if disabled (optional automation)
                if not rotation_enabled and key_details['KeyMetadata']['KeyState'] == 'Enabled':
                    logger.warning(f"Enabling rotation for key {key_id}")
                    kms_client.enable_key_rotation(KeyId=key_id)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Key rotation monitoring completed',
                'keysChecked': len(rotation_status),
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error monitoring key rotation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package Lambda function
    cd "${TEMP_DIR}"
    zip -q key-rotation-monitor.zip key_rotation_monitor.py
    cd - > /dev/null
    
    # Wait for IAM role to be available
    print_status "$YELLOW" "[INFO] Waiting for IAM role to be available..."
    sleep 10
    
    # Deploy Lambda function
    local lambda_arn
    lambda_arn=$(aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role" \
        --handler key_rotation_monitor.lambda_handler \
        --zip-file "fileb://${TEMP_DIR}/key-rotation-monitor.zip" \
        --timeout 60 \
        --memory-size 128 \
        --query FunctionArn --output text)
    
    if [[ -z "$lambda_arn" ]]; then
        print_status "$RED" "[ERROR] Failed to create Lambda function"
        exit 1
    fi
    
    # Configure CloudWatch log retention
    aws logs create-log-group \
        --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    aws logs put-retention-policy \
        --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}" \
        --retention-in-days 30
    
    log "INFO" "Lambda function created: $lambda_arn"
    
    # Store Lambda ARN for later use
    echo "$lambda_arn" > "${SCRIPT_DIR}/.lambda_arn"
    
    print_status "$GREEN" "✅ Lambda function created successfully"
}

# Create CloudWatch Events rule
create_cloudwatch_events() {
    print_status "$BLUE" "[INFO] Creating CloudWatch Events rule for automated execution..."
    
    local lambda_arn
    lambda_arn=$(cat "${SCRIPT_DIR}/.lambda_arn")
    
    # Create CloudWatch Events rule for weekly execution
    aws events put-rule \
        --name "${LAMBDA_FUNCTION_NAME}-schedule" \
        --schedule-expression "rate(7 days)" \
        --description "Weekly KMS key rotation monitoring" \
        --state ENABLED
    
    # Add Lambda function as target
    aws events put-targets \
        --rule "${LAMBDA_FUNCTION_NAME}-schedule" \
        --targets "Id"="1","Arn"="$lambda_arn"
    
    # Grant CloudWatch Events permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id allow-cloudwatch-events \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${LAMBDA_FUNCTION_NAME}-schedule"
    
    log "INFO" "CloudWatch Events rule created: ${LAMBDA_FUNCTION_NAME}-schedule"
    log "INFO" "Weekly execution schedule configured"
    
    print_status "$GREEN" "✅ CloudWatch Events rule configured"
}

# Create demonstration data
create_demo_data() {
    print_status "$BLUE" "[INFO] Creating envelope encryption demonstration..."
    
    # Create sample data for encryption demonstration
    cat > "${TEMP_DIR}/sample-data.txt" << 'EOF'
Sensitive enterprise data requiring encryption
Additional confidential information
Financial records and customer data
EOF
    
    # Upload sample data with server-side encryption
    aws s3 cp "${TEMP_DIR}/sample-data.txt" "s3://${S3_BUCKET_NAME}/secure-data.txt" \
        --server-side-encryption aws:kms \
        --ssekms-key-id "alias/${KMS_KEY_ALIAS}"
    
    log "INFO" "Sample encrypted data uploaded to S3"
    
    print_status "$GREEN" "✅ Envelope encryption demonstration completed"
}

# Validate deployment
validate_deployment() {
    print_status "$BLUE" "[INFO] Validating deployment..."
    
    # Check KMS key rotation status
    local rotation_status
    rotation_status=$(aws kms get-key-rotation-status \
        --key-id "alias/${KMS_KEY_ALIAS}" \
        --query KeyRotationEnabled --output text)
    
    if [[ "$rotation_status" != "True" ]]; then
        print_status "$RED" "[ERROR] KMS key rotation is not enabled"
        exit 1
    fi
    
    # Test Lambda function execution
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload '{}' \
        "${TEMP_DIR}/response.json" > /dev/null
    
    local status_code
    status_code=$(jq -r '.statusCode' "${TEMP_DIR}/response.json" 2>/dev/null || echo "null")
    
    if [[ "$status_code" != "200" ]]; then
        print_status "$RED" "[ERROR] Lambda function test failed"
        cat "${TEMP_DIR}/response.json"
        exit 1
    fi
    
    # Verify S3 encryption
    local encryption_check
    encryption_check=$(aws s3api get-bucket-encryption \
        --bucket "$S3_BUCKET_NAME" \
        --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
        --output text)
    
    if [[ "$encryption_check" != "aws:kms" ]]; then
        print_status "$RED" "[ERROR] S3 bucket encryption validation failed"
        exit 1
    fi
    
    print_status "$GREEN" "✅ Deployment validation completed successfully"
}

# Print deployment summary
print_summary() {
    print_status "$GREEN" "\n🎉 Deployment completed successfully!"
    
    cat << EOF

📋 DEPLOYMENT SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔐 KMS Configuration:
   • Customer Master Key: alias/$KMS_KEY_ALIAS
   • Automatic Rotation: Enabled (annual)

📦 S3 Storage:
   • Bucket Name: $S3_BUCKET_NAME
   • Encryption: KMS with CMK
   • Versioning: Enabled

⚡ Lambda Function:
   • Function Name: $LAMBDA_FUNCTION_NAME
   • Runtime: Python 3.9
   • Schedule: Weekly monitoring

📊 CloudWatch Events:
   • Rule Name: ${LAMBDA_FUNCTION_NAME}-schedule
   • Frequency: Every 7 days

📁 Configuration Files:
   • Environment: ${SCRIPT_DIR}/.deployment_env
   • Logs: $LOG_FILE

🔧 Next Steps:
   1. Review CloudWatch logs for Lambda function execution
   2. Test envelope encryption with additional data
   3. Monitor key rotation compliance through scheduled execution
   4. Use destroy.sh script for cleanup when needed

💰 Cost Considerations:
   • KMS: ~\$1/month per CMK + API charges
   • Lambda: ~\$0.20/month for weekly executions
   • S3: Based on storage usage
   • CloudWatch: Minimal logging charges

For more information, see the recipe documentation.

EOF
}

# Main execution
main() {
    print_status "$BLUE" "🚀 Starting Enterprise KMS Envelope Encryption Deployment"
    print_status "$BLUE" "============================================================"
    
    log "INFO" "Deployment started at $(date)"
    
    validate_aws_prerequisites
    validate_permissions
    setup_environment
    create_kms_key
    create_s3_bucket
    create_iam_resources
    create_lambda_function
    create_cloudwatch_events
    create_demo_data
    validate_deployment
    print_summary
    
    log "INFO" "Deployment completed successfully at $(date)"
}

# Execute main function
main "$@"