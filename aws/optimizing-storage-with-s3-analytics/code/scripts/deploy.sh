#!/bin/bash

#
# deploy.sh - S3 Inventory and Storage Analytics Reporting Deployment Script
#
# This script deploys AWS S3 Inventory and Storage Analytics infrastructure
# including S3 buckets, inventory configurations, analytics configurations,
# Athena database, Lambda function, and EventBridge schedules.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for S3, Athena, Lambda, IAM, EventBridge
# - jq installed for JSON processing
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#

set -euo pipefail

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for failed deployments
cleanup_on_error() {
    log_warning "Deployment failed. Starting cleanup of partial resources..."
    
    # Remove S3 bucket contents and buckets if they exist
    if aws s3 ls "s3://${SOURCE_BUCKET}" &>/dev/null; then
        aws s3 rm "s3://${SOURCE_BUCKET}" --recursive || true
        aws s3 rb "s3://${SOURCE_BUCKET}" || true
    fi
    
    if aws s3 ls "s3://${DEST_BUCKET}" &>/dev/null; then
        aws s3 rm "s3://${DEST_BUCKET}" --recursive || true
        aws s3 rb "s3://${DEST_BUCKET}" || true
    fi
    
    # Remove Lambda function if it exists
    if aws lambda get-function --function-name "StorageAnalyticsFunction-${RANDOM_SUFFIX}" &>/dev/null; then
        aws lambda delete-function --function-name "StorageAnalyticsFunction-${RANDOM_SUFFIX}" || true
    fi
    
    # Remove IAM role if it exists
    if aws iam get-role --role-name "StorageAnalyticsLambdaRole-${RANDOM_SUFFIX}" &>/dev/null; then
        aws iam detach-role-policy --role-name "StorageAnalyticsLambdaRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
        aws iam delete-role-policy --role-name "StorageAnalyticsLambdaRole-${RANDOM_SUFFIX}" \
            --policy-name StorageAnalyticsPolicy || true
        aws iam delete-role --role-name "StorageAnalyticsLambdaRole-${RANDOM_SUFFIX}" || true
    fi
    
    log_error "Cleanup completed. Please check for any remaining resources manually."
}

# Set trap for error handling
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure'."
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq for JSON processing."
    fi
    
    # Check required permissions (basic check)
    local test_bucket="test-permissions-$(date +%s)"
    if aws s3 mb "s3://${test_bucket}" --region "${AWS_REGION}" &>/dev/null; then
        aws s3 rb "s3://${test_bucket}" &>/dev/null
    else
        error_exit "Insufficient S3 permissions. Please ensure you have S3 admin access."
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export SOURCE_BUCKET="storage-analytics-source-${RANDOM_SUFFIX}"
    export DEST_BUCKET="storage-analytics-reports-${RANDOM_SUFFIX}"
    export INVENTORY_CONFIG_ID="daily-inventory-config"
    export ANALYTICS_CONFIG_ID="storage-class-analysis"
    export ATHENA_DATABASE="s3_inventory_db_${RANDOM_SUFFIX//-/_}"
    export ATHENA_TABLE="inventory_table"
    export LAMBDA_FUNCTION_NAME="StorageAnalyticsFunction-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="StorageAnalyticsLambdaRole-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="StorageAnalyticsSchedule-${RANDOM_SUFFIX}"
    export CLOUDWATCH_DASHBOARD_NAME="S3-Storage-Analytics-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
}

# Create S3 buckets and upload sample data
create_s3_resources() {
    log_info "Creating S3 buckets and uploading sample data..."
    
    # Create source bucket
    aws s3 mb "s3://${SOURCE_BUCKET}" --region "${AWS_REGION}"
    log_success "Created source bucket: ${SOURCE_BUCKET}"
    
    # Create destination bucket
    aws s3 mb "s3://${DEST_BUCKET}" --region "${AWS_REGION}"
    log_success "Created destination bucket: ${DEST_BUCKET}"
    
    # Upload sample data
    echo "Sample data for storage analytics - $(date)" > sample-file.txt
    aws s3 cp sample-file.txt "s3://${SOURCE_BUCKET}/data/sample-file.txt"
    aws s3 cp sample-file.txt "s3://${SOURCE_BUCKET}/logs/access-log.txt"
    aws s3 cp sample-file.txt "s3://${SOURCE_BUCKET}/archive/old-data.txt"
    rm sample-file.txt
    
    log_success "Uploaded sample data to source bucket"
}

# Configure S3 Inventory
configure_s3_inventory() {
    log_info "Configuring S3 Inventory..."
    
    # Create inventory configuration
    cat > inventory-config.json << EOF
{
    "Id": "${INVENTORY_CONFIG_ID}",
    "IsEnabled": true,
    "IncludedObjectVersions": "Current",
    "Schedule": {
        "Frequency": "Daily"
    },
    "OptionalFields": [
        "Size",
        "LastModifiedDate",
        "StorageClass",
        "ETag",
        "ReplicationStatus",
        "EncryptionStatus"
    ],
    "Destination": {
        "S3BucketDestination": {
            "AccountId": "${AWS_ACCOUNT_ID}",
            "Bucket": "arn:aws:s3:::${DEST_BUCKET}",
            "Format": "CSV",
            "Prefix": "inventory-reports/"
        }
    }
}
EOF
    
    # Apply inventory configuration
    aws s3api put-bucket-inventory-configuration \
        --bucket "${SOURCE_BUCKET}" \
        --id "${INVENTORY_CONFIG_ID}" \
        --inventory-configuration file://inventory-config.json
    
    rm inventory-config.json
    log_success "Configured S3 Inventory for daily reporting"
}

# Set up destination bucket policy
setup_bucket_policy() {
    log_info "Setting up destination bucket policy..."
    
    # Create bucket policy for inventory destination
    cat > inventory-bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "InventoryDestinationBucketPolicy",
            "Effect": "Allow",
            "Principal": {
                "Service": "s3.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${DEST_BUCKET}/*",
            "Condition": {
                "ArnLike": {
                    "aws:SourceArn": "arn:aws:s3:::${SOURCE_BUCKET}"
                },
                "StringEquals": {
                    "aws:SourceAccount": "${AWS_ACCOUNT_ID}",
                    "s3:x-amz-acl": "bucket-owner-full-control"
                }
            }
        }
    ]
}
EOF
    
    # Apply bucket policy
    aws s3api put-bucket-policy \
        --bucket "${DEST_BUCKET}" \
        --policy file://inventory-bucket-policy.json
    
    rm inventory-bucket-policy.json
    log_success "Applied destination bucket policy for inventory reports"
}

# Configure Storage Class Analysis
configure_storage_analytics() {
    log_info "Configuring Storage Class Analysis..."
    
    # Create storage analytics configuration
    cat > analytics-config.json << EOF
{
    "Id": "${ANALYTICS_CONFIG_ID}",
    "Filter": {
        "Prefix": "data/"
    },
    "StorageClassAnalysis": {
        "DataExport": {
            "OutputSchemaVersion": "V_1",
            "Destination": {
                "S3BucketDestination": {
                    "Format": "CSV",
                    "BucketAccountId": "${AWS_ACCOUNT_ID}",
                    "Bucket": "arn:aws:s3:::${DEST_BUCKET}",
                    "Prefix": "analytics-reports/"
                }
            }
        }
    }
}
EOF
    
    # Apply analytics configuration
    aws s3api put-bucket-analytics-configuration \
        --bucket "${SOURCE_BUCKET}" \
        --id "${ANALYTICS_CONFIG_ID}" \
        --analytics-configuration file://analytics-config.json
    
    rm analytics-config.json
    log_success "Configured Storage Class Analysis for optimization insights"
}

# Create Athena database
create_athena_database() {
    log_info "Creating Athena database and configuring query environment..."
    
    # Create Athena database
    local query_execution_id=$(aws athena start-query-execution \
        --query-string "CREATE DATABASE IF NOT EXISTS ${ATHENA_DATABASE}" \
        --result-configuration "OutputLocation=s3://${DEST_BUCKET}/athena-results/" \
        --work-group primary \
        --query 'QueryExecutionId' --output text)
    
    # Wait for query to complete
    local status="RUNNING"
    while [[ "${status}" == "RUNNING" || "${status}" == "QUEUED" ]]; do
        sleep 5
        status=$(aws athena get-query-execution \
            --query-execution-id "${query_execution_id}" \
            --query 'QueryExecution.Status.State' --output text)
    done
    
    if [[ "${status}" != "SUCCEEDED" ]]; then
        error_exit "Failed to create Athena database. Status: ${status}"
    fi
    
    # Configure Athena query result location
    aws athena update-work-group \
        --work-group primary \
        --configuration-updates \
        "ResultConfigurationUpdates={OutputLocation=s3://${DEST_BUCKET}/athena-results/}"
    
    log_success "Created Athena database and configured query environment"
}

# Create sample Athena queries
create_athena_queries() {
    log_info "Creating sample Athena queries..."
    
    mkdir -p athena-queries
    
    # Storage class distribution query
    cat > athena-queries/storage-class-distribution.sql << EOF
-- Query to analyze storage class distribution
SELECT 
    storage_class,
    COUNT(*) as object_count,
    SUM(size) as total_size_bytes,
    ROUND(SUM(size) / 1024.0 / 1024.0 / 1024.0, 2) as total_size_gb
FROM ${ATHENA_DATABASE}.${ATHENA_TABLE}
GROUP BY storage_class
ORDER BY total_size_bytes DESC;
EOF
    
    # Old objects analysis query
    cat > athena-queries/old-objects-analysis.sql << EOF
-- Query to find objects older than 30 days
SELECT 
    key,
    size,
    storage_class,
    last_modified_date,
    DATE_DIFF('day', DATE_PARSE(last_modified_date, '%Y-%m-%dT%H:%i:%s.%fZ'), CURRENT_DATE) as days_old
FROM ${ATHENA_DATABASE}.${ATHENA_TABLE}
WHERE DATE_DIFF('day', DATE_PARSE(last_modified_date, '%Y-%m-%dT%H:%i:%s.%fZ'), CURRENT_DATE) > 30
ORDER BY days_old DESC;
EOF
    
    # Prefix analysis query
    cat > athena-queries/prefix-analysis.sql << EOF
-- Query to analyze storage by prefix
SELECT 
    CASE 
        WHEN key LIKE 'data/%' THEN 'data'
        WHEN key LIKE 'logs/%' THEN 'logs'
        WHEN key LIKE 'archive/%' THEN 'archive'
        ELSE 'other'
    END as prefix_category,
    COUNT(*) as object_count,
    SUM(size) as total_size_bytes,
    AVG(size) as avg_size_bytes
FROM ${ATHENA_DATABASE}.${ATHENA_TABLE}
GROUP BY 1
ORDER BY total_size_bytes DESC;
EOF
    
    log_success "Created sample Athena queries for inventory analysis"
}

# Create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log_info "Creating CloudWatch dashboard..."
    
    # Create dashboard configuration
    cat > dashboard-config.json << EOF
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
                    ["AWS/S3", "BucketSizeBytes", "BucketName", "${SOURCE_BUCKET}", "StorageType", "StandardStorage"],
                    [".", ".", ".", ".", ".", "StandardIAStorage"],
                    [".", "NumberOfObjects", ".", ".", ".", "AllStorageTypes"]
                ],
                "period": 86400,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "S3 Storage Metrics"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/S3", "AllRequests", "BucketName", "${SOURCE_BUCKET}"]
                ],
                "period": 3600,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "S3 Request Metrics"
            }
        }
    ]
}
EOF
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${CLOUDWATCH_DASHBOARD_NAME}" \
        --dashboard-body file://dashboard-config.json
    
    rm dashboard-config.json
    log_success "Created CloudWatch dashboard for storage analytics monitoring"
}

# Create IAM role for Lambda
create_lambda_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    # Create trust policy
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
    
    # Create Lambda execution role
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document file://lambda-trust-policy.json
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for Athena and S3 access
    cat > lambda-custom-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "athena:StartQueryExecution",
                "athena:GetQueryExecution",
                "athena:GetQueryResults",
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket",
                "glue:GetDatabase",
                "glue:GetTable"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create and attach custom policy
    aws iam put-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name StorageAnalyticsPolicy \
        --policy-document file://lambda-custom-policy.json
    
    rm lambda-trust-policy.json lambda-custom-policy.json
    
    # Wait for role to be available
    log_info "Waiting for IAM role to propagate..."
    sleep 15
    
    log_success "Created IAM role for Lambda function"
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for automated reporting..."
    
    # Create Lambda function code
    cat > lambda-function.py << 'EOF'
import json
import boto3
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    athena = boto3.client('athena')
    s3 = boto3.client('s3')
    
    # Configuration
    database = os.environ['ATHENA_DATABASE']
    table = os.environ['ATHENA_TABLE']
    output_bucket = os.environ['DEST_BUCKET']
    
    # Query for storage optimization insights
    query = f"""
    SELECT 
        storage_class,
        COUNT(*) as object_count,
        SUM(size) as total_size_bytes,
        ROUND(SUM(size) / 1024.0 / 1024.0 / 1024.0, 2) as total_size_gb,
        ROUND(AVG(size) / 1024.0 / 1024.0, 2) as avg_size_mb
    FROM {database}.{table}
    GROUP BY storage_class
    ORDER BY total_size_bytes DESC;
    """
    
    try:
        # Execute query
        response = athena.start_query_execution(
            QueryString=query,
            ResultConfiguration={
                'OutputLocation': f's3://{output_bucket}/athena-results/'
            },
            WorkGroup='primary'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Storage analytics query executed successfully',
                'queryExecutionId': response['QueryExecutionId']
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
EOF
    
    # Create deployment package
    zip lambda-function.zip lambda-function.py
    
    # Get Lambda role ARN
    local lambda_role_arn=$(aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${lambda_role_arn}" \
        --handler lambda-function.lambda_handler \
        --zip-file fileb://lambda-function.zip \
        --environment Variables="{
            ATHENA_DATABASE=${ATHENA_DATABASE},
            ATHENA_TABLE=${ATHENA_TABLE},
            DEST_BUCKET=${DEST_BUCKET}
        }"
    
    rm lambda-function.py lambda-function.zip
    log_success "Created Lambda function for automated reporting"
}

# Configure EventBridge schedule
configure_eventbridge_schedule() {
    log_info "Configuring EventBridge schedule for automated reports..."
    
    # Create EventBridge rule for daily reports
    aws events put-rule \
        --name "${EVENTBRIDGE_RULE_NAME}" \
        --schedule-expression "rate(1 day)" \
        --description "Daily storage analytics reporting"
    
    # Get Lambda ARN
    local lambda_arn=$(aws lambda get-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --query 'Configuration.FunctionArn' --output text)
    
    # Add Lambda as target
    aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}" \
        --targets "Id=1,Arn=${lambda_arn}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id storage-analytics-schedule \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}"
    
    log_success "Configured EventBridge schedule for automated daily reports"
}

# Create deployment summary
create_deployment_summary() {
    log_info "Creating deployment summary..."
    
    cat > deployment-summary.txt << EOF
S3 Inventory and Storage Analytics Deployment Summary
===================================================

Deployment completed successfully at: $(date)

Resources Created:
- Source Bucket: ${SOURCE_BUCKET}
- Destination Bucket: ${DEST_BUCKET}
- S3 Inventory Configuration: ${INVENTORY_CONFIG_ID}
- Storage Analytics Configuration: ${ANALYTICS_CONFIG_ID}
- Athena Database: ${ATHENA_DATABASE}
- Lambda Function: ${LAMBDA_FUNCTION_NAME}
- IAM Role: ${IAM_ROLE_NAME}
- EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}
- CloudWatch Dashboard: ${CLOUDWATCH_DASHBOARD_NAME}

AWS Region: ${AWS_REGION}
AWS Account ID: ${AWS_ACCOUNT_ID}

Next Steps:
1. Wait 24-48 hours for first S3 Inventory report to be generated
2. Monitor CloudWatch dashboard for storage metrics
3. Use sample Athena queries in athena-queries/ directory for analysis
4. Review EventBridge schedule for automated reporting

Important Notes:
- Storage Class Analysis requires 30 days of observation for meaningful insights
- Estimated monthly cost: \$5-15 for small datasets
- All queries can be customized for your specific use cases

For cleanup, run: ./destroy.sh
EOF
    
    log_success "Deployment summary created: deployment-summary.txt"
}

# Main deployment function
main() {
    log_info "Starting S3 Inventory and Storage Analytics deployment..."
    
    check_prerequisites
    setup_environment
    create_s3_resources
    configure_s3_inventory
    setup_bucket_policy
    configure_storage_analytics
    create_athena_database
    create_athena_queries
    create_cloudwatch_dashboard
    create_lambda_iam_role
    create_lambda_function
    configure_eventbridge_schedule
    create_deployment_summary
    
    log_success "🎉 S3 Inventory and Storage Analytics deployment completed successfully!"
    log_info "📊 CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${CLOUDWATCH_DASHBOARD_NAME}"
    log_info "🔍 Athena Console: https://console.aws.amazon.com/athena/home?region=${AWS_REGION}"
    log_info "📁 S3 Source Bucket: https://console.aws.amazon.com/s3/buckets/${SOURCE_BUCKET}"
    log_info "📁 S3 Reports Bucket: https://console.aws.amazon.com/s3/buckets/${DEST_BUCKET}"
    log_info ""
    log_info "⏱️  First inventory report will be available in 24-48 hours"
    log_info "📈 Storage analytics insights will be meaningful after 30 days"
    log_info ""
    log_info "For detailed information, see deployment-summary.txt"
}

# Execute main function
main "$@"