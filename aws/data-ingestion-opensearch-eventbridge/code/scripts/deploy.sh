#!/bin/bash

# Deploy script for Automated Data Ingestion Pipelines with OpenSearch and EventBridge
# This script creates all infrastructure components for the data ingestion solution

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version (require v2)
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ! "$AWS_CLI_VERSION" =~ ^2\. ]]; then
        error "AWS CLI v2 is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set up AWS credentials."
        exit 1
    fi
    
    # Check required permissions (basic check)
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error "Unable to retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    # Set resource names
    export BUCKET_NAME="data-ingestion-${RANDOM_SUFFIX}"
    export OPENSEARCH_DOMAIN="analytics-domain-${RANDOM_SUFFIX}"
    export PIPELINE_NAME="data-pipeline-${RANDOM_SUFFIX}"
    export SCHEDULE_GROUP_NAME="ingestion-schedules-${RANDOM_SUFFIX}"
    export PIPELINE_ROLE_NAME="OpenSearchIngestionRole-${RANDOM_SUFFIX}"
    export SCHEDULER_ROLE_NAME="EventBridgeSchedulerRole-${RANDOM_SUFFIX}"
    
    # Save environment to file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
BUCKET_NAME=${BUCKET_NAME}
OPENSEARCH_DOMAIN=${OPENSEARCH_DOMAIN}
PIPELINE_NAME=${PIPELINE_NAME}
SCHEDULE_GROUP_NAME=${SCHEDULE_GROUP_NAME}
PIPELINE_ROLE_NAME=${PIPELINE_ROLE_NAME}
SCHEDULER_ROLE_NAME=${SCHEDULER_ROLE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment configured - Region: $AWS_REGION, Account: $AWS_ACCOUNT_ID"
    log "Resource suffix: $RANDOM_SUFFIX"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for data storage..."
    
    # Create S3 bucket with proper error handling for existing buckets
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket ${BUCKET_NAME} already exists"
    else
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3 mb s3://${BUCKET_NAME}
        else
            aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
        fi
        success "S3 bucket created: ${BUCKET_NAME}"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket ${BUCKET_NAME} \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket ${BUCKET_NAME} \
        --public-access-block-configuration \
        'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
    
    success "S3 bucket configured with security settings"
}

# Function to create IAM role for OpenSearch Ingestion
create_opensearch_iam_role() {
    log "Creating IAM role for OpenSearch Ingestion..."
    
    # Create trust policy
    cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "osis-pipelines.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create permission policy
    cat > permissions-policy.json << EOF
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
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "es:ESHttpPost",
        "es:ESHttpPut"
      ],
      "Resource": "arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${OPENSEARCH_DOMAIN}/*"
    }
  ]
}
EOF
    
    # Create the IAM role (handle existing role)
    if aws iam get-role --role-name ${PIPELINE_ROLE_NAME} &>/dev/null; then
        warning "IAM role ${PIPELINE_ROLE_NAME} already exists"
    else
        aws iam create-role \
            --role-name ${PIPELINE_ROLE_NAME} \
            --assume-role-policy-document file://trust-policy.json \
            --tags "Key=Environment,Value=Development" "Key=Service,Value=DataIngestion"
        success "IAM role created: ${PIPELINE_ROLE_NAME}"
    fi
    
    # Attach/update the permissions policy
    aws iam put-role-policy \
        --role-name ${PIPELINE_ROLE_NAME} \
        --policy-name OpenSearchIngestionPolicy \
        --policy-document file://permissions-policy.json
    
    export PIPELINE_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PIPELINE_ROLE_NAME}"
    success "IAM role configured: ${PIPELINE_ROLE_ARN}"
}

# Function to create OpenSearch domain
create_opensearch_domain() {
    log "Creating OpenSearch domain..."
    
    # Check if domain already exists
    if aws opensearch describe-domain --domain-name ${OPENSEARCH_DOMAIN} &>/dev/null; then
        warning "OpenSearch domain ${OPENSEARCH_DOMAIN} already exists"
        export OPENSEARCH_ENDPOINT=$(aws opensearch describe-domain \
            --domain-name ${OPENSEARCH_DOMAIN} \
            --query 'DomainStatus.Endpoint' --output text)
        return 0
    fi
    
    # Create domain configuration
    cat > domain-config.json << EOF
{
  "DomainName": "${OPENSEARCH_DOMAIN}",
  "EngineVersion": "OpenSearch_2.3",
  "ClusterConfig": {
    "InstanceType": "t3.small.search",
    "InstanceCount": 1,
    "DedicatedMasterEnabled": false
  },
  "EBSOptions": {
    "EBSEnabled": true,
    "VolumeType": "gp3",
    "VolumeSize": 20
  },
  "AccessPolicies": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::${AWS_ACCOUNT_ID}:root\"},\"Action\":\"es:*\",\"Resource\":\"arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${OPENSEARCH_DOMAIN}/*\"}]}",
  "DomainEndpointOptions": {
    "EnforceHTTPS": true
  },
  "EncryptionAtRestOptions": {
    "Enabled": true
  },
  "NodeToNodeEncryptionOptions": {
    "Enabled": true
  },
  "TagList": [
    {"Key": "Environment", "Value": "Development"},
    {"Key": "Service", "Value": "DataIngestion"}
  ]
}
EOF
    
    # Create the OpenSearch domain
    aws opensearch create-domain --cli-input-json file://domain-config.json
    success "OpenSearch domain creation initiated: ${OPENSEARCH_DOMAIN}"
    
    # Wait for domain to be ready
    log "Waiting for OpenSearch domain to be ready (this may take 10-15 minutes)..."
    aws opensearch wait domain-available --domain-name ${OPENSEARCH_DOMAIN}
    
    # Get domain endpoint
    export OPENSEARCH_ENDPOINT=$(aws opensearch describe-domain \
        --domain-name ${OPENSEARCH_DOMAIN} \
        --query 'DomainStatus.Endpoint' --output text)
    
    success "OpenSearch domain is ready at: https://${OPENSEARCH_ENDPOINT}"
}

# Function to create OpenSearch Ingestion pipeline
create_ingestion_pipeline() {
    log "Creating OpenSearch Ingestion pipeline..."
    
    # Check if pipeline already exists
    if aws osis get-pipeline --pipeline-name ${PIPELINE_NAME} &>/dev/null; then
        warning "OpenSearch Ingestion pipeline ${PIPELINE_NAME} already exists"
        return 0
    fi
    
    # Create pipeline configuration
    cat > pipeline-config.yaml << EOF
data-ingestion-pipeline:
  source:
    s3:
      notification_type: "sqs"
      codec:
        newline: null
      compression: "none"
      bucket: "${BUCKET_NAME}"
      object_key:
        include_keys:
          - "logs/**"
          - "metrics/**"
          - "events/**"
  processor:
    - date:
        from_time_received: true
        destination: "@timestamp"
    - mutate:
        rename_keys:
          message: "raw_message"
    - grok:
        match:
          raw_message: ['%{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:level} %{GREEDYDATA:message}']
  sink:
    - opensearch:
        hosts: ["https://${OPENSEARCH_ENDPOINT}"]
        index: "application-logs-%{yyyy.MM.dd}"
        aws:
          region: "${AWS_REGION}"
          sts_role_arn: "${PIPELINE_ROLE_ARN}"
          serverless: false
EOF
    
    # Create the pipeline
    aws osis create-pipeline \
        --pipeline-name ${PIPELINE_NAME} \
        --min-units 1 \
        --max-units 4 \
        --pipeline-configuration-body file://pipeline-config.yaml \
        --tags "Environment=Development,Project=DataIngestion"
    
    # Wait for pipeline to be ready
    log "Waiting for OpenSearch Ingestion pipeline to be ready..."
    aws osis wait pipeline-available --pipeline-name ${PIPELINE_NAME}
    
    success "OpenSearch Ingestion pipeline created and ready: ${PIPELINE_NAME}"
}

# Function to create EventBridge Scheduler resources
create_scheduler_resources() {
    log "Creating EventBridge Scheduler resources..."
    
    # Create schedule group
    if aws scheduler get-schedule-group --name ${SCHEDULE_GROUP_NAME} &>/dev/null; then
        warning "Schedule group ${SCHEDULE_GROUP_NAME} already exists"
    else
        aws scheduler create-schedule-group \
            --name ${SCHEDULE_GROUP_NAME} \
            --tags "Environment=Development,Service=DataIngestion"
        success "Schedule group created: ${SCHEDULE_GROUP_NAME}"
    fi
    
    # Create IAM role for EventBridge Scheduler
    create_scheduler_iam_role
    
    # Create schedules
    create_pipeline_schedules
}

# Function to create IAM role for EventBridge Scheduler
create_scheduler_iam_role() {
    log "Creating IAM role for EventBridge Scheduler..."
    
    # Create trust policy
    cat > scheduler-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "scheduler.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create permissions policy
    cat > scheduler-permissions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "osis:StartPipeline",
        "osis:StopPipeline",
        "osis:GetPipeline"
      ],
      "Resource": "arn:aws:osis:${AWS_REGION}:${AWS_ACCOUNT_ID}:pipeline/${PIPELINE_NAME}"
    }
  ]
}
EOF
    
    # Create scheduler role (handle existing role)
    if aws iam get-role --role-name ${SCHEDULER_ROLE_NAME} &>/dev/null; then
        warning "IAM role ${SCHEDULER_ROLE_NAME} already exists"
    else
        aws iam create-role \
            --role-name ${SCHEDULER_ROLE_NAME} \
            --assume-role-policy-document file://scheduler-trust-policy.json \
            --tags "Key=Environment,Value=Development" "Key=Service,Value=Scheduler"
        success "Scheduler IAM role created: ${SCHEDULER_ROLE_NAME}"
    fi
    
    # Attach permissions policy
    aws iam put-role-policy \
        --role-name ${SCHEDULER_ROLE_NAME} \
        --policy-name SchedulerPipelinePolicy \
        --policy-document file://scheduler-permissions-policy.json
    
    export SCHEDULER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${SCHEDULER_ROLE_NAME}"
    success "Scheduler IAM role configured: ${SCHEDULER_ROLE_ARN}"
}

# Function to create pipeline schedules
create_pipeline_schedules() {
    log "Creating pipeline start/stop schedules..."
    
    # Create start schedule
    if aws scheduler get-schedule --name "start-ingestion-pipeline" --group-name ${SCHEDULE_GROUP_NAME} &>/dev/null; then
        warning "Start schedule already exists"
    else
        aws scheduler create-schedule \
            --name "start-ingestion-pipeline" \
            --group-name ${SCHEDULE_GROUP_NAME} \
            --schedule-expression "cron(0 8 * * ? *)" \
            --target "{
                \"Arn\": \"arn:aws:osis:${AWS_REGION}:${AWS_ACCOUNT_ID}:pipeline/${PIPELINE_NAME}\",
                \"RoleArn\": \"${SCHEDULER_ROLE_ARN}\",
                \"Input\": \"{\\\"action\\\": \\\"start\\\"}\",
                \"RetryPolicy\": {
                    \"MaximumRetryAttempts\": 3,
                    \"MaximumEventAge\": 3600
                }
            }" \
            --flexible-time-window '{"Mode": "FLEXIBLE", "MaximumWindowInMinutes": 15}' \
            --description "Daily start of data ingestion pipeline"
        success "Pipeline start schedule created (daily at 8 AM UTC)"
    fi
    
    # Create stop schedule
    if aws scheduler get-schedule --name "stop-ingestion-pipeline" --group-name ${SCHEDULE_GROUP_NAME} &>/dev/null; then
        warning "Stop schedule already exists"
    else
        aws scheduler create-schedule \
            --name "stop-ingestion-pipeline" \
            --group-name ${SCHEDULE_GROUP_NAME} \
            --schedule-expression "cron(0 18 * * ? *)" \
            --target "{
                \"Arn\": \"arn:aws:osis:${AWS_REGION}:${AWS_ACCOUNT_ID}:pipeline/${PIPELINE_NAME}\",
                \"RoleArn\": \"${SCHEDULER_ROLE_ARN}\",
                \"Input\": \"{\\\"action\\\": \\\"stop\\\"}\",
                \"RetryPolicy\": {
                    \"MaximumRetryAttempts\": 3,
                    \"MaximumEventAge\": 3600
                }
            }" \
            --flexible-time-window '{"Mode": "FLEXIBLE", "MaximumWindowInMinutes": 15}' \
            --description "Daily stop of data ingestion pipeline"
        success "Pipeline stop schedule created (daily at 6 PM UTC)"
    fi
}

# Function to upload sample data
upload_sample_data() {
    log "Uploading sample data to S3..."
    
    # Create sample log data
    cat > sample-logs.log << EOF
2023-07-12T08:30:00Z INFO Application started successfully
2023-07-12T08:30:15Z DEBUG Database connection established
2023-07-12T08:30:30Z WARN High memory usage detected: 85%
2023-07-12T08:30:45Z ERROR Failed to process user request: timeout
2023-07-12T08:31:00Z INFO Request processed successfully
EOF
    
    # Upload sample data to S3
    aws s3 cp sample-logs.log s3://${BUCKET_NAME}/logs/2023/07/12/
    
    # Create sample metrics data
    cat > sample-metrics.json << EOF
{"timestamp": "2023-07-12T08:30:00Z", "metric": "cpu_usage", "value": 45.2, "unit": "percent"}
{"timestamp": "2023-07-12T08:30:30Z", "metric": "memory_usage", "value": 67.8, "unit": "percent"}
{"timestamp": "2023-07-12T08:31:00Z", "metric": "disk_usage", "value": 23.4, "unit": "percent"}
EOF
    
    # Upload metrics data to S3
    aws s3 cp sample-metrics.json s3://${BUCKET_NAME}/metrics/2023/07/12/
    
    success "Sample data uploaded to S3"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check OpenSearch domain
    DOMAIN_STATUS=$(aws opensearch describe-domain \
        --domain-name ${OPENSEARCH_DOMAIN} \
        --query 'DomainStatus.DomainStatus' --output text)
    
    if [[ "$DOMAIN_STATUS" == "Active" ]]; then
        success "OpenSearch domain is active"
    else
        warning "OpenSearch domain status: $DOMAIN_STATUS"
    fi
    
    # Check ingestion pipeline
    PIPELINE_STATUS=$(aws osis get-pipeline \
        --pipeline-name ${PIPELINE_NAME} \
        --query 'Pipeline.Status' --output text)
    
    if [[ "$PIPELINE_STATUS" == "ACTIVE" ]]; then
        success "OpenSearch Ingestion pipeline is active"
    else
        warning "Pipeline status: $PIPELINE_STATUS"
    fi
    
    # Check schedules
    SCHEDULE_COUNT=$(aws scheduler list-schedules \
        --group-name ${SCHEDULE_GROUP_NAME} \
        --query 'length(Schedules)' --output text)
    
    if [[ "$SCHEDULE_COUNT" == "2" ]]; then
        success "Both pipeline schedules are created"
    else
        warning "Expected 2 schedules, found: $SCHEDULE_COUNT"
    fi
    
    success "Deployment verification completed"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f trust-policy.json permissions-policy.json domain-config.json
    rm -f pipeline-config.yaml scheduler-trust-policy.json scheduler-permissions-policy.json
    rm -f sample-logs.log sample-metrics.json
    success "Temporary files cleaned up"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "=================================="
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=================================="
    echo ""
    echo "📋 Resource Summary:"
    echo "   S3 Bucket: ${BUCKET_NAME}"
    echo "   OpenSearch Domain: ${OPENSEARCH_DOMAIN}"
    echo "   OpenSearch Endpoint: https://${OPENSEARCH_ENDPOINT}"
    echo "   Ingestion Pipeline: ${PIPELINE_NAME}"
    echo "   Schedule Group: ${SCHEDULE_GROUP_NAME}"
    echo "   Pipeline IAM Role: ${PIPELINE_ROLE_NAME}"
    echo "   Scheduler IAM Role: ${SCHEDULER_ROLE_NAME}"
    echo ""
    echo "⏰ Scheduled Operations:"
    echo "   Pipeline starts daily at 8:00 AM UTC"
    echo "   Pipeline stops daily at 6:00 PM UTC"
    echo ""
    echo "🔗 Next Steps:"
    echo "   1. Access OpenSearch Dashboards at: https://${OPENSEARCH_ENDPOINT}/_dashboards"
    echo "   2. Monitor pipeline status: aws osis get-pipeline --pipeline-name ${PIPELINE_NAME}"
    echo "   3. View processed data in OpenSearch indices"
    echo ""
    echo "🧹 To clean up all resources, run: ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    echo "🚀 Starting deployment of Automated Data Ingestion Pipelines"
    echo "============================================================="
    echo ""
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_opensearch_iam_role
    create_opensearch_domain
    create_ingestion_pipeline
    create_scheduler_resources
    upload_sample_data
    verify_deployment
    cleanup_temp_files
    display_summary
    
    success "Deployment completed successfully! 🎉"
}

# Trap to ensure cleanup on script exit
trap 'cleanup_temp_files' EXIT

# Run main function
main "$@"