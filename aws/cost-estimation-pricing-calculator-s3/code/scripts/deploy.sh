#!/bin/bash

# Cost Estimation Planning with Pricing Calculator and S3 - Deployment Script
# This script deploys infrastructure for cost estimation storage and management
# Version: 1.0
# Last Updated: 2025-01-16

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy-$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_status "$RED" "❌ AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        print_status "$RED" "❌ AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        print_status "$YELLOW" "⚠️  jq is not installed. Some features may be limited."
    fi
    
    print_status "$GREEN" "✅ Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Get AWS configuration
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        print_status "$RED" "❌ Failed to get AWS Account ID"
        exit 1
    fi
    
    # Generate unique identifiers for resources
    if command -v aws &> /dev/null && aws secretsmanager get-random-password --help &> /dev/null; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
    fi
    
    # Set resource names
    export BUCKET_NAME="cost-estimates-${RANDOM_SUFFIX}"
    export PROJECT_NAME="web-app-migration"
    export SNS_TOPIC_NAME="${PROJECT_NAME}-budget-alerts"
    
    log "INFO" "Environment setup completed"
    log "INFO" "AWS Region: ${AWS_REGION}"
    log "INFO" "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "INFO" "Bucket Name: ${BUCKET_NAME}"
    log "INFO" "Project Name: ${PROJECT_NAME}"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "INFO" "Creating S3 bucket for cost estimates..."
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$BLUE" "🔍 DRY RUN: Would create S3 bucket: ${BUCKET_NAME}"
        return
    fi
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        print_status "$YELLOW" "⚠️  Bucket ${BUCKET_NAME} already exists"
        return
    fi
    
    # Create bucket with region-specific configuration
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "${BUCKET_NAME}" 2>&1 | tee -a "$LOG_FILE"
    else
        aws s3api create-bucket \
            --bucket "${BUCKET_NAME}" \
            --region "${AWS_REGION}" \
            --create-bucket-configuration LocationConstraint="${AWS_REGION}" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Wait for bucket to be available
    aws s3api wait bucket-exists --bucket "${BUCKET_NAME}"
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled 2>&1 | tee -a "$LOG_FILE"
    
    # Apply server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]' 2>&1 | tee -a "$LOG_FILE"
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "${BUCKET_NAME}" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" 2>&1 | tee -a "$LOG_FILE"
    
    print_status "$GREEN" "✅ S3 bucket created with security and versioning enabled"
}

# Function to create folder structure
create_folder_structure() {
    log "INFO" "Creating organized folder structure..."
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$BLUE" "🔍 DRY RUN: Would create folder structure in bucket"
        return
    fi
    
    # Create folder structure
    local folders=(
        "estimates/2025/Q1/"
        "estimates/2025/Q2/"
        "projects/${PROJECT_NAME}/"
        "archived/"
    )
    
    for folder in "${folders[@]}"; do
        aws s3api put-object \
            --bucket "${BUCKET_NAME}" \
            --key "$folder" \
            --content-length 0 2>&1 | tee -a "$LOG_FILE"
    done
    
    print_status "$GREEN" "✅ Organized folder structure created"
}

# Function to configure lifecycle policy
configure_lifecycle_policy() {
    log "INFO" "Configuring lifecycle policy for cost optimization..."
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$BLUE" "🔍 DRY RUN: Would configure lifecycle policy"
        return
    fi
    
    # Create lifecycle policy file
    cat > "${SCRIPT_DIR}/lifecycle-policy.json" << 'EOF'
{
    "Rules": [
        {
            "ID": "CostEstimateLifecycle",
            "Status": "Enabled",
            "Filter": {"Prefix": "estimates/"},
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ]
        }
    ]
}
EOF
    
    # Apply lifecycle policy to bucket
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "${BUCKET_NAME}" \
        --lifecycle-configuration "file://${SCRIPT_DIR}/lifecycle-policy.json" 2>&1 | tee -a "$LOG_FILE"
    
    print_status "$GREEN" "✅ Lifecycle policy configured for automatic cost optimization"
}

# Function to upload sample estimate
upload_sample_estimate() {
    log "INFO" "Creating and uploading sample cost estimate..."
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$BLUE" "🔍 DRY RUN: Would upload sample estimate files"
        return
    fi
    
    # Create sample estimate file
    cat > "${SCRIPT_DIR}/sample-estimate.csv" << 'EOF'
Service,Configuration,Monthly Cost,Annual Cost
Amazon EC2,t3.medium Linux,30.37,364.44
Amazon S3,100GB Standard Storage,2.30,27.60
Amazon RDS,db.t3.micro PostgreSQL,13.32,159.84
Total,,46.99,563.88
EOF
    
    # Upload estimate with tags and metadata
    aws s3 cp "${SCRIPT_DIR}/sample-estimate.csv" \
        "s3://${BUCKET_NAME}/projects/${PROJECT_NAME}/estimate-$(date +%Y%m%d).csv" \
        --metadata "project=${PROJECT_NAME},created-by=cost-team,estimate-date=$(date +%Y-%m-%d)" \
        --tagging "Project=${PROJECT_NAME}&Department=Finance&EstimateType=Monthly" 2>&1 | tee -a "$LOG_FILE"
    
    # Create estimate summary document
    cat > "${SCRIPT_DIR}/estimate-summary.txt" << EOF
Cost Estimate Summary - ${PROJECT_NAME}
Generated: $(date)

Estimated Monthly Cost: \$46.99
Estimated Annual Cost: \$563.88

Services Included:
- EC2 t3.medium instance
- S3 storage (100GB)
- RDS PostgreSQL database

Notes: This estimate assumes standard usage patterns
EOF
    
    aws s3 cp "${SCRIPT_DIR}/estimate-summary.txt" \
        "s3://${BUCKET_NAME}/projects/${PROJECT_NAME}/summary-$(date +%Y%m%d).txt" 2>&1 | tee -a "$LOG_FILE"
    
    print_status "$GREEN" "✅ Sample cost estimates uploaded with metadata and tags"
}

# Function to create SNS topic
create_sns_topic() {
    log "INFO" "Creating SNS topic for budget notifications..."
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$BLUE" "🔍 DRY RUN: Would create SNS topic: ${SNS_TOPIC_NAME}"
        return
    fi
    
    # Create SNS topic
    aws sns create-topic --name "${SNS_TOPIC_NAME}" 2>&1 | tee -a "$LOG_FILE"
    
    # Get topic ARN
    export TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --query 'Attributes.TopicArn' --output text 2>/dev/null)
    
    if [ -z "$TOPIC_ARN" ]; then
        print_status "$RED" "❌ Failed to get SNS topic ARN"
        exit 1
    fi
    
    print_status "$GREEN" "✅ SNS topic created: ${TOPIC_ARN}"
}

# Function to create budget
create_budget() {
    log "INFO" "Creating budget with alert notifications..."
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$BLUE" "🔍 DRY RUN: Would create budget: ${PROJECT_NAME}-budget"
        return
    fi
    
    # Create budget policy file
    cat > "${SCRIPT_DIR}/budget-policy.json" << EOF
{
    "BudgetName": "${PROJECT_NAME}-budget",
    "BudgetLimit": {
        "Amount": "50.00",
        "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {
        "TagKey": ["Project"],
        "TagValue": ["${PROJECT_NAME}"]
    }
}
EOF
    
    # Create budget with notification
    aws budgets create-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget "file://${SCRIPT_DIR}/budget-policy.json" \
        --notifications-with-subscribers "[{
            \"Notification\": {
                \"NotificationType\": \"ACTUAL\",
                \"ComparisonOperator\": \"GREATER_THAN\",
                \"Threshold\": 80,
                \"ThresholdType\": \"PERCENTAGE\"
            },
            \"Subscribers\": [{
                \"SubscriptionType\": \"SNS\",
                \"Address\": \"${TOPIC_ARN}\"
            }]
        }]" 2>&1 | tee -a "$LOG_FILE"
    
    print_status "$GREEN" "✅ Budget created with 80% threshold alert"
}

# Function to create deployment summary
create_deployment_summary() {
    log "INFO" "Creating deployment summary..."
    
    cat > "${SCRIPT_DIR}/deployment-summary.txt" << EOF
=== Cost Estimation Infrastructure Deployment Summary ===
Deployment Date: $(date)
AWS Region: ${AWS_REGION}
AWS Account ID: ${AWS_ACCOUNT_ID}

Resources Created:
- S3 Bucket: ${BUCKET_NAME}
  - Versioning: Enabled
  - Encryption: AES256
  - Public Access: Blocked
  - Lifecycle Policy: Configured

- SNS Topic: ${SNS_TOPIC_NAME}
  - ARN: ${TOPIC_ARN}

- AWS Budget: ${PROJECT_NAME}-budget
  - Monthly Limit: \$50.00
  - Alert Threshold: 80%

Sample Files Created:
- sample-estimate.csv
- estimate-summary.txt

Next Steps:
1. Access AWS Pricing Calculator: https://calculator.aws/#/
2. Create your cost estimates
3. Upload estimates to S3 bucket: s3://${BUCKET_NAME}
4. Monitor costs through AWS Budgets console

For cleanup, run: ./destroy.sh
EOF
    
    print_status "$GREEN" "✅ Deployment summary created: ${SCRIPT_DIR}/deployment-summary.txt"
}

# Function to validate deployment
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    local errors=0
    
    # Check S3 bucket
    if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        print_status "$RED" "❌ S3 bucket validation failed"
        ((errors++))
    else
        print_status "$GREEN" "✅ S3 bucket is accessible"
    fi
    
    # Check SNS topic
    if ! aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" &>/dev/null; then
        print_status "$RED" "❌ SNS topic validation failed"
        ((errors++))
    else
        print_status "$GREEN" "✅ SNS topic is accessible"
    fi
    
    # Check budget
    if ! aws budgets describe-budget --account-id "${AWS_ACCOUNT_ID}" --budget-name "${PROJECT_NAME}-budget" &>/dev/null; then
        print_status "$RED" "❌ Budget validation failed"
        ((errors++))
    else
        print_status "$GREEN" "✅ Budget is configured correctly"
    fi
    
    if [ $errors -eq 0 ]; then
        print_status "$GREEN" "✅ All resources validated successfully"
        return 0
    else
        print_status "$RED" "❌ Validation failed with $errors errors"
        return 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Cost Estimation Planning infrastructure on AWS

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without making changes
    -v, --verbose       Enable verbose logging
    
ENVIRONMENT VARIABLES:
    AWS_REGION          Override AWS region (default: from AWS CLI config)
    PROJECT_NAME        Override project name (default: web-app-migration)

EXAMPLES:
    $0                  Deploy with default settings
    $0 --dry-run        Preview deployment without making changes
    $0 --verbose        Deploy with detailed logging

EOF
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "INFO" "Cleaning up temporary files..."
    rm -f "${SCRIPT_DIR}/lifecycle-policy.json"
    rm -f "${SCRIPT_DIR}/budget-policy.json"
    rm -f "${SCRIPT_DIR}/sample-estimate.csv"
    rm -f "${SCRIPT_DIR}/estimate-summary.txt"
}

# Main deployment function
main() {
    print_status "$BLUE" "🚀 Starting Cost Estimation Infrastructure Deployment"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$YELLOW" "🔍 DRY RUN MODE: No resources will be created"
    fi
    
    # Execute deployment steps with error handling
    trap 'log "ERROR" "Deployment failed at line $LINENO"; cleanup_temp_files; exit 1' ERR
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_folder_structure
    configure_lifecycle_policy
    upload_sample_estimate
    create_sns_topic
    create_budget
    
    if [ "$DRY_RUN" = false ]; then
        validate_deployment
        create_deployment_summary
    fi
    
    cleanup_temp_files
    
    print_status "$GREEN" "🎉 Deployment completed successfully!"
    
    if [ "$DRY_RUN" = false ]; then
        echo ""
        print_status "$BLUE" "📋 Deployment Summary:"
        cat "${SCRIPT_DIR}/deployment-summary.txt"
        echo ""
        print_status "$YELLOW" "💡 Next Steps:"
        echo "1. Visit AWS Pricing Calculator: https://calculator.aws/#/"
        echo "2. Create cost estimates for your projects"
        echo "3. Upload estimates to S3: s3://${BUCKET_NAME}"
        echo "4. Monitor costs through AWS Budgets console"
        echo ""
        print_status "$BLUE" "📝 Log file: $LOG_FILE"
    fi
}

# Run main function
main "$@"