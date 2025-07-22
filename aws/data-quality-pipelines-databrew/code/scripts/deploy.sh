#!/bin/bash

# Data Quality Pipelines with DataBrew
# Deployment Script
# 
# This script deploys the complete infrastructure for automated data quality pipelines
# using AWS Glue DataBrew, Amazon EventBridge, and AWS Lambda.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warn "Running in DRY RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    info "$description"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY RUN] Would execute: $cmd"
        return 0
    else
        if eval "$cmd"; then
            log "✅ $description completed successfully"
            return 0
        else
            error "❌ Failed to execute: $description"
            return 1
        fi
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check required permissions
    info "Checking AWS permissions..."
    
    # Test basic permissions
    if ! aws sts get-caller-identity &> /dev/null; then
        error "Unable to verify AWS credentials"
    fi
    
    log "✅ Prerequisites check passed"
}

# Environment setup
setup_environment() {
    log "Setting up environment variables..."
    
    # Set environment variables
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        error "Unable to determine AWS account ID"
    fi
    
    # Generate unique identifiers for resources
    if [ "$DRY_RUN" = "false" ]; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    else
        RANDOM_SUFFIX="dryrun"
    fi
    
    export BUCKET_NAME="data-quality-pipeline-${RANDOM_SUFFIX}"
    export DATASET_NAME="customer-data-${RANDOM_SUFFIX}"
    export RULESET_NAME="customer-quality-rules-${RANDOM_SUFFIX}"
    export PROFILE_JOB_NAME="quality-assessment-job-${RANDOM_SUFFIX}"
    
    # Create deployment log file
    LOG_FILE="deployment-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    
    info "Deployment log: $LOG_FILE"
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "Resource Suffix: $RANDOM_SUFFIX"
    
    log "✅ Environment setup completed"
}

# Create S3 bucket and sample data
create_s3_resources() {
    log "Creating S3 bucket and sample data..."
    
    # Create S3 bucket
    execute_cmd "aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}" \
        "Creating S3 bucket: ${BUCKET_NAME}"
    
    # Create sample data with quality issues
    if [ "$DRY_RUN" = "false" ]; then
        cat > customer-data.csv << 'EOF'
customer_id,name,email,age,registration_date,purchase_amount
1,John Doe,john.doe@email.com,35,2024-01-15,299.99
2,Jane Smith,jane.smith@email.com,28,2024-02-20,159.50
3,Bob Johnson,,42,2024-01-30,899.00
4,Alice Brown,alice.brown@email.com,-5,2024-03-10,49.99
5,Charlie Wilson,invalid-email,30,2024-02-15,
6,Diana Davis,diana.davis@email.com,25,2024-01-05,199.75
EOF
    fi
    
    execute_cmd "aws s3 cp customer-data.csv s3://${BUCKET_NAME}/raw-data/customer-data.csv" \
        "Uploading sample data to S3"
    
    log "✅ S3 resources created successfully"
}

# Create IAM role for DataBrew
create_databrew_role() {
    log "Creating IAM role for DataBrew..."
    
    # Create trust policy
    if [ "$DRY_RUN" = "false" ]; then
        cat > databrew-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "databrew.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    fi
    
    # Create the DataBrew service role
    execute_cmd "aws iam create-role \
        --role-name DataBrewServiceRole-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://databrew-trust-policy.json" \
        "Creating DataBrew service role"
    
    # Get role ARN
    if [ "$DRY_RUN" = "false" ]; then
        DATABREW_ROLE_ARN=$(aws iam get-role \
            --role-name DataBrewServiceRole-${RANDOM_SUFFIX} \
            --query 'Role.Arn' --output text)
    else
        DATABREW_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/DataBrewServiceRole-${RANDOM_SUFFIX}"
    fi
    
    export DATABREW_ROLE_ARN
    
    # Attach managed policy
    execute_cmd "aws iam attach-role-policy \
        --role-name DataBrewServiceRole-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueDataBrewServiceRole" \
        "Attaching DataBrew service policy"
    
    # Wait for role propagation
    if [ "$DRY_RUN" = "false" ]; then
        info "Waiting for IAM role propagation..."
        sleep 10
    fi
    
    log "✅ DataBrew IAM role created: ${DATABREW_ROLE_ARN}"
}

# Create DataBrew dataset
create_databrew_dataset() {
    log "Creating DataBrew dataset..."
    
    execute_cmd "aws databrew create-dataset \
        --name ${DATASET_NAME} \
        --format CSV \
        --format-options '{\"Csv\":{\"Delimiter\":\",\",\"HeaderRow\":true}}' \
        --input '{\"S3InputDefinition\":{\"Bucket\":\"${BUCKET_NAME}\",\"Key\":\"raw-data/customer-data.csv\"}}' \
        --tags Environment=Development,Purpose=DataQuality" \
        "Creating DataBrew dataset"
    
    log "✅ DataBrew dataset created: ${DATASET_NAME}"
}

# Create data quality ruleset
create_data_quality_ruleset() {
    log "Creating data quality ruleset..."
    
    # Get dataset ARN
    if [ "$DRY_RUN" = "false" ]; then
        DATASET_ARN=$(aws databrew describe-dataset \
            --name ${DATASET_NAME} \
            --query 'ResourceArn' --output text)
    else
        DATASET_ARN="arn:aws:databrew:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/${DATASET_NAME}"
    fi
    
    # Create ruleset JSON
    if [ "$DRY_RUN" = "false" ]; then
        cat > ruleset-rules.json << 'EOF'
[
  {
    "Name": "EmailFormatValidation",
    "CheckExpression": ":col1 matches \"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$\"",
    "SubstitutionMap": {
      ":col1": "`email`"
    },
    "Threshold": {
      "Value": 90.0,
      "Type": "GREATER_THAN_OR_EQUAL",
      "Unit": "PERCENTAGE"
    }
  },
  {
    "Name": "AgeRangeValidation",
    "CheckExpression": ":col1 between :val1 and :val2",
    "SubstitutionMap": {
      ":col1": "`age`",
      ":val1": "0",
      ":val2": "120"
    },
    "Threshold": {
      "Value": 95.0,
      "Type": "GREATER_THAN_OR_EQUAL",
      "Unit": "PERCENTAGE"
    }
  },
  {
    "Name": "PurchaseAmountNotNull",
    "CheckExpression": ":col1 is not null",
    "SubstitutionMap": {
      ":col1": "`purchase_amount`"
    },
    "Threshold": {
      "Value": 90.0,
      "Type": "GREATER_THAN_OR_EQUAL",
      "Unit": "PERCENTAGE"
    }
  }
]
EOF
    fi
    
    execute_cmd "aws databrew create-ruleset \
        --name ${RULESET_NAME} \
        --target-arn ${DATASET_ARN} \
        --rules file://ruleset-rules.json \
        --tags Environment=Development,Purpose=DataQuality" \
        "Creating data quality ruleset"
    
    log "✅ Data quality ruleset created: ${RULESET_NAME}"
}

# Create Lambda function for event processing
create_lambda_function() {
    log "Creating Lambda function for event processing..."
    
    # Create Lambda function code
    if [ "$DRY_RUN" = "false" ]; then
        cat > lambda-function.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event, default=str)}")
    
    # Extract DataBrew validation result details
    detail = event.get('detail', {})
    validation_state = detail.get('validationState')
    dataset_name = detail.get('datasetName')
    job_name = detail.get('jobName')
    ruleset_name = detail.get('rulesetName')
    
    if validation_state == 'FAILED':
        # Initialize AWS clients
        sns = boto3.client('sns')
        s3 = boto3.client('s3')
        
        # Send notification
        message = f"""
        Data Quality Alert - Validation Failed
        
        Dataset: {dataset_name}
        Job: {job_name}
        Ruleset: {ruleset_name}
        Timestamp: {datetime.now().isoformat()}
        
        Action Required: Review data quality report and investigate source data issues.
        """
        
        # Publish to SNS (if topic ARN is provided)
        topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if topic_arn:
            sns.publish(
                TopicArn=topic_arn,
                Subject='Data Quality Validation Failed',
                Message=message
            )
        
        print(f"Data quality validation failed for dataset: {dataset_name}")
        
    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed validation result: {validation_state}')
    }
EOF
    fi
    
    # Create deployment package
    execute_cmd "zip lambda-function.zip lambda-function.py" \
        "Creating Lambda deployment package"
    
    # Create Lambda trust policy
    if [ "$DRY_RUN" = "false" ]; then
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
    fi
    
    # Create Lambda execution role
    execute_cmd "aws iam create-role \
        --role-name DataQualityLambdaRole-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://lambda-trust-policy.json" \
        "Creating Lambda execution role"
    
    # Get Lambda role ARN
    if [ "$DRY_RUN" = "false" ]; then
        LAMBDA_ROLE_ARN=$(aws iam get-role \
            --role-name DataQualityLambdaRole-${RANDOM_SUFFIX} \
            --query 'Role.Arn' --output text)
    else
        LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/DataQualityLambdaRole-${RANDOM_SUFFIX}"
    fi
    
    export LAMBDA_ROLE_ARN
    
    # Attach basic Lambda execution policy
    execute_cmd "aws iam attach-role-policy \
        --role-name DataQualityLambdaRole-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Attaching Lambda basic execution policy"
    
    # Create additional permissions policy
    if [ "$DRY_RUN" = "false" ]; then
        cat > lambda-permissions-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    fi
    
    execute_cmd "aws iam put-role-policy \
        --role-name DataQualityLambdaRole-${RANDOM_SUFFIX} \
        --policy-name DataQualityPermissions \
        --policy-document file://lambda-permissions-policy.json" \
        "Creating Lambda permissions policy"
    
    # Wait for role propagation
    if [ "$DRY_RUN" = "false" ]; then
        info "Waiting for IAM role propagation..."
        sleep 10
    fi
    
    # Create Lambda function
    execute_cmd "aws lambda create-function \
        --function-name DataQualityProcessor-${RANDOM_SUFFIX} \
        --runtime python3.9 \
        --role ${LAMBDA_ROLE_ARN} \
        --handler lambda-function.lambda_handler \
        --zip-file fileb://lambda-function.zip \
        --timeout 60 \
        --tags Environment=Development,Purpose=DataQuality" \
        "Creating Lambda function"
    
    # Get Lambda function ARN
    if [ "$DRY_RUN" = "false" ]; then
        LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
            --function-name DataQualityProcessor-${RANDOM_SUFFIX} \
            --query 'Configuration.FunctionArn' --output text)
    else
        LAMBDA_FUNCTION_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:DataQualityProcessor-${RANDOM_SUFFIX}"
    fi
    
    export LAMBDA_FUNCTION_ARN
    
    log "✅ Lambda function created: ${LAMBDA_FUNCTION_ARN}"
}

# Create EventBridge rule
create_eventbridge_rule() {
    log "Creating EventBridge rule for DataBrew events..."
    
    # Create EventBridge rule
    execute_cmd "aws events put-rule \
        --name DataBrewValidationRule-${RANDOM_SUFFIX} \
        --description \"Route DataBrew validation events to Lambda\" \
        --event-pattern '{\"source\":[\"aws.databrew\"],\"detail-type\":[\"DataBrew Ruleset Validation Result\"],\"detail\":{\"validationState\":[\"FAILED\"]}}' \
        --state ENABLED \
        --tags Environment=Development,Purpose=DataQuality" \
        "Creating EventBridge rule"
    
    # Add Lambda function as target
    execute_cmd "aws events put-targets \
        --rule DataBrewValidationRule-${RANDOM_SUFFIX} \
        --targets \"Id\"=\"1\",\"Arn\"=\"${LAMBDA_FUNCTION_ARN}\"" \
        "Adding Lambda target to EventBridge rule"
    
    # Grant EventBridge permission to invoke Lambda
    execute_cmd "aws lambda add-permission \
        --function-name DataQualityProcessor-${RANDOM_SUFFIX} \
        --statement-id databrew-eventbridge-permission \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/DataBrewValidationRule-${RANDOM_SUFFIX}" \
        "Granting EventBridge permission to invoke Lambda"
    
    log "✅ EventBridge rule created and configured"
}

# Create DataBrew profile job
create_profile_job() {
    log "Creating DataBrew profile job..."
    
    execute_cmd "aws databrew create-profile-job \
        --name ${PROFILE_JOB_NAME} \
        --dataset-name ${DATASET_NAME} \
        --role-arn ${DATABREW_ROLE_ARN} \
        --output-location '{\"Bucket\":\"${BUCKET_NAME}\",\"Key\":\"quality-reports/\"}' \
        --validation-configurations '[{\"RulesetArn\":\"arn:aws:databrew:${AWS_REGION}:${AWS_ACCOUNT_ID}:ruleset/${RULESET_NAME}\",\"ValidationMode\":\"CHECK_ALL\"}]' \
        --configuration '{\"DatasetStatisticsConfiguration\":{\"IncludedStatistics\":[\"COMPLETENESS\",\"VALIDITY\",\"UNIQUENESS\",\"CORRELATION\"]}}' \
        --max-capacity 5 \
        --timeout 120 \
        --tags Environment=Development,Purpose=DataQuality" \
        "Creating DataBrew profile job"
    
    log "✅ DataBrew profile job created: ${PROFILE_JOB_NAME}"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    # Create deployment info file
    if [ "$DRY_RUN" = "false" ]; then
        cat > deployment-info.json << EOF
{
  "deploymentTimestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "awsRegion": "${AWS_REGION}",
  "awsAccountId": "${AWS_ACCOUNT_ID}",
  "resourceSuffix": "${RANDOM_SUFFIX}",
  "resources": {
    "s3Bucket": "${BUCKET_NAME}",
    "datasetName": "${DATASET_NAME}",
    "rulesetName": "${RULESET_NAME}",
    "profileJobName": "${PROFILE_JOB_NAME}",
    "databrewRoleArn": "${DATABREW_ROLE_ARN}",
    "lambdaFunctionArn": "${LAMBDA_FUNCTION_ARN}",
    "lambdaRoleArn": "${LAMBDA_ROLE_ARN}",
    "eventbridgeRuleName": "DataBrewValidationRule-${RANDOM_SUFFIX}"
  }
}
EOF
    fi
    
    log "✅ Deployment information saved to deployment-info.json"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    if [ "$DRY_RUN" = "false" ]; then
        rm -f customer-data.csv
        rm -f lambda-function.zip
        rm -f lambda-function.py
        rm -f databrew-trust-policy.json
        rm -f lambda-trust-policy.json
        rm -f lambda-permissions-policy.json
        rm -f ruleset-rules.json
    fi
    
    log "✅ Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting AWS Data Quality Pipeline deployment..."
    
    # Check if user wants to proceed
    if [ "$DRY_RUN" = "false" ]; then
        echo
        info "This script will create the following AWS resources:"
        info "- S3 bucket for data storage and reports"
        info "- IAM roles for DataBrew and Lambda"
        info "- DataBrew dataset and ruleset"
        info "- Lambda function for event processing"
        info "- EventBridge rule for automation"
        info "- DataBrew profile job"
        echo
        
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_s3_resources
    create_databrew_role
    create_databrew_dataset
    create_data_quality_ruleset
    create_lambda_function
    create_eventbridge_rule
    create_profile_job
    save_deployment_info
    cleanup_temp_files
    
    log "🎉 Deployment completed successfully!"
    echo
    info "Next steps:"
    info "1. Run the profile job: aws databrew start-job-run --name ${PROFILE_JOB_NAME}"
    info "2. Monitor job progress in the AWS DataBrew console"
    info "3. View quality reports in S3 bucket: ${BUCKET_NAME}/quality-reports/"
    info "4. Check Lambda logs for event processing: /aws/lambda/DataQualityProcessor-${RANDOM_SUFFIX}"
    echo
    info "Deployment information saved to: deployment-info.json"
    warn "Remember to run destroy.sh to clean up resources when done testing"
    echo
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may have been created. Check AWS console and run cleanup if needed."' INT TERM

# Run main function
main "$@"