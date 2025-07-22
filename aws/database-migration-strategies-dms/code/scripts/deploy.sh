#!/bin/bash

# Deployment script for AWS DMS Database Migration Recipe
# This script deploys the complete DMS migration infrastructure

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
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
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some outputs may not be formatted nicely."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Please set AWS_REGION environment variable or configure default region."
        exit 1
    fi
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export DMS_REPLICATION_INSTANCE_ID="dms-replication-${RANDOM_SUFFIX}"
    export DMS_SUBNET_GROUP_ID="dms-subnet-group-${RANDOM_SUFFIX}"
    export SOURCE_ENDPOINT_ID="source-endpoint-${RANDOM_SUFFIX}"
    export TARGET_ENDPOINT_ID="target-endpoint-${RANDOM_SUFFIX}"
    export MIGRATION_TASK_ID="migration-task-${RANDOM_SUFFIX}"
    export CDC_TASK_ID="cdc-task-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="dms-migration-logs-${RANDOM_SUFFIX}"
    
    # Store variables in file for cleanup script
    cat > .env_vars << EOF
DMS_REPLICATION_INSTANCE_ID="${DMS_REPLICATION_INSTANCE_ID}"
DMS_SUBNET_GROUP_ID="${DMS_SUBNET_GROUP_ID}"
SOURCE_ENDPOINT_ID="${SOURCE_ENDPOINT_ID}"
TARGET_ENDPOINT_ID="${TARGET_ENDPOINT_ID}"
MIGRATION_TASK_ID="${MIGRATION_TASK_ID}"
CDC_TASK_ID="${CDC_TASK_ID}"
S3_BUCKET_NAME="${S3_BUCKET_NAME}"
AWS_REGION="${AWS_REGION}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
EOF
    
    success "Environment variables configured"
    log "Random suffix: ${RANDOM_SUFFIX}"
}

# Function to get VPC information
get_vpc_info() {
    log "Getting VPC information..."
    
    # Get default VPC
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
        error "No default VPC found. Please create a VPC or specify a custom VPC ID."
        exit 1
    fi
    
    # Get subnet IDs
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[*].SubnetId' --output text)
    
    if [[ -z "$SUBNET_IDS" ]]; then
        error "No subnets found in VPC ${VPC_ID}"
        exit 1
    fi
    
    success "VPC information retrieved - VPC ID: ${VPC_ID}"
    echo "VPC_ID=${VPC_ID}" >> .env_vars
    echo "SUBNET_IDS=\"${SUBNET_IDS}\"" >> .env_vars
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for migration logs..."
    
    # Create S3 bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb s3://${S3_BUCKET_NAME}
    else
        aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket ${S3_BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    success "S3 bucket created: ${S3_BUCKET_NAME}"
}

# Function to create DMS subnet group
create_subnet_group() {
    log "Creating DMS subnet group..."
    
    aws dms create-replication-subnet-group \
        --replication-subnet-group-identifier ${DMS_SUBNET_GROUP_ID} \
        --replication-subnet-group-description "DMS subnet group for migration" \
        --subnet-ids ${SUBNET_IDS} \
        --tags Key=Name,Value=dms-migration-subnet-group \
               Key=Environment,Value=migration \
               Key=CreatedBy,Value=dms-migration-recipe
    
    success "DMS subnet group created: ${DMS_SUBNET_GROUP_ID}"
}

# Function to create DMS replication instance
create_replication_instance() {
    log "Creating DMS replication instance (this may take 5-10 minutes)..."
    
    aws dms create-replication-instance \
        --replication-instance-identifier ${DMS_REPLICATION_INSTANCE_ID} \
        --replication-instance-class dms.t3.medium \
        --allocated-storage 100 \
        --multi-az \
        --engine-version 3.5.2 \
        --replication-subnet-group-identifier ${DMS_SUBNET_GROUP_ID} \
        --publicly-accessible \
        --tags Key=Name,Value=dms-migration-instance \
               Key=Environment,Value=migration \
               Key=CreatedBy,Value=dms-migration-recipe
    
    log "Waiting for replication instance to become available..."
    aws dms wait replication-instance-available \
        --replication-instance-identifier ${DMS_REPLICATION_INSTANCE_ID}
    
    success "DMS replication instance is available: ${DMS_REPLICATION_INSTANCE_ID}"
}

# Function to create endpoints
create_endpoints() {
    log "Creating source and target endpoints..."
    
    # Check if endpoint configuration file exists
    if [[ ! -f "endpoint-config.json" ]]; then
        warning "endpoint-config.json not found. Creating template file..."
        cat > endpoint-config.json << 'EOF'
{
  "source": {
    "engine": "mysql",
    "server": "your-source-db-hostname",
    "port": 3306,
    "database": "your-source-database",
    "username": "your-source-username",
    "password": "your-source-password",
    "extra_attributes": "initstmt=SET foreign_key_checks=0"
  },
  "target": {
    "engine": "mysql",
    "server": "your-target-rds-hostname",
    "port": 3306,
    "database": "your-target-database",
    "username": "your-target-username",
    "password": "your-target-password",
    "extra_attributes": "initstmt=SET foreign_key_checks=0"
  }
}
EOF
        error "Please configure endpoint-config.json with your database connection details and run the script again."
        exit 1
    fi
    
    # Read endpoint configuration
    SOURCE_ENGINE=$(jq -r '.source.engine' endpoint-config.json)
    SOURCE_SERVER=$(jq -r '.source.server' endpoint-config.json)
    SOURCE_PORT=$(jq -r '.source.port' endpoint-config.json)
    SOURCE_DATABASE=$(jq -r '.source.database' endpoint-config.json)
    SOURCE_USERNAME=$(jq -r '.source.username' endpoint-config.json)
    SOURCE_PASSWORD=$(jq -r '.source.password' endpoint-config.json)
    SOURCE_EXTRA=$(jq -r '.source.extra_attributes' endpoint-config.json)
    
    TARGET_ENGINE=$(jq -r '.target.engine' endpoint-config.json)
    TARGET_SERVER=$(jq -r '.target.server' endpoint-config.json)
    TARGET_PORT=$(jq -r '.target.port' endpoint-config.json)
    TARGET_DATABASE=$(jq -r '.target.database' endpoint-config.json)
    TARGET_USERNAME=$(jq -r '.target.username' endpoint-config.json)
    TARGET_PASSWORD=$(jq -r '.target.password' endpoint-config.json)
    TARGET_EXTRA=$(jq -r '.target.extra_attributes' endpoint-config.json)
    
    # Create source endpoint
    aws dms create-endpoint \
        --endpoint-identifier ${SOURCE_ENDPOINT_ID} \
        --endpoint-type source \
        --engine-name ${SOURCE_ENGINE} \
        --server-name ${SOURCE_SERVER} \
        --port ${SOURCE_PORT} \
        --database-name ${SOURCE_DATABASE} \
        --username ${SOURCE_USERNAME} \
        --password ${SOURCE_PASSWORD} \
        --extra-connection-attributes "${SOURCE_EXTRA}" \
        --tags Key=Name,Value=source-endpoint \
               Key=Environment,Value=migration \
               Key=CreatedBy,Value=dms-migration-recipe
    
    # Create target endpoint
    aws dms create-endpoint \
        --endpoint-identifier ${TARGET_ENDPOINT_ID} \
        --endpoint-type target \
        --engine-name ${TARGET_ENGINE} \
        --server-name ${TARGET_SERVER} \
        --port ${TARGET_PORT} \
        --database-name ${TARGET_DATABASE} \
        --username ${TARGET_USERNAME} \
        --password ${TARGET_PASSWORD} \
        --extra-connection-attributes "${TARGET_EXTRA}" \
        --tags Key=Name,Value=target-endpoint \
               Key=Environment,Value=migration \
               Key=CreatedBy,Value=dms-migration-recipe
    
    success "Source and target endpoints created"
}

# Function to test endpoint connections
test_connections() {
    log "Testing endpoint connections..."
    
    # Get replication instance ARN
    RI_ARN=$(aws dms describe-replication-instances \
        --replication-instance-identifier ${DMS_REPLICATION_INSTANCE_ID} \
        --query 'ReplicationInstances[0].ReplicationInstanceArn' --output text)
    
    # Get source endpoint ARN
    SOURCE_ARN=$(aws dms describe-endpoints \
        --endpoint-identifier ${SOURCE_ENDPOINT_ID} \
        --query 'Endpoints[0].EndpointArn' --output text)
    
    # Get target endpoint ARN
    TARGET_ARN=$(aws dms describe-endpoints \
        --endpoint-identifier ${TARGET_ENDPOINT_ID} \
        --query 'Endpoints[0].EndpointArn' --output text)
    
    # Test source connection
    aws dms test-connection \
        --replication-instance-arn ${RI_ARN} \
        --endpoint-arn ${SOURCE_ARN}
    
    # Test target connection
    aws dms test-connection \
        --replication-instance-arn ${RI_ARN} \
        --endpoint-arn ${TARGET_ARN}
    
    success "Connection tests initiated. Check DMS console for results."
}

# Function to create table mapping and task settings
create_configurations() {
    log "Creating table mapping and task settings..."
    
    # Create table mapping
    cat > table-mapping.json << 'EOF'
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "1",
      "object-locator": {
        "schema-name": "%",
        "table-name": "%"
      },
      "rule-action": "include",
      "filters": []
    },
    {
      "rule-type": "transformation",
      "rule-id": "2",
      "rule-name": "2",
      "rule-target": "schema",
      "object-locator": {
        "schema-name": "%"
      },
      "rule-action": "rename",
      "value": "migrated_${schema-name}"
    }
  ]
}
EOF
    
    # Create task settings
    cat > task-settings.json << EOF
{
  "TargetMetadata": {
    "TargetSchema": "",
    "SupportLobs": true,
    "FullLobMode": false,
    "LobChunkSize": 0,
    "LimitedSizeLobMode": true,
    "LobMaxSize": 32,
    "InlineLobMaxSize": 0,
    "LoadMaxFileSize": 0,
    "ParallelLoadThreads": 0,
    "ParallelLoadBufferSize": 0,
    "BatchApplyEnabled": false,
    "TaskRecoveryTableEnabled": false,
    "ParallelApplyThreads": 0,
    "ParallelApplyBufferSize": 0,
    "ParallelApplyQueuesPerThread": 0
  },
  "FullLoadSettings": {
    "TargetTablePrepMode": "DROP_AND_CREATE",
    "CreatePkAfterFullLoad": false,
    "StopTaskCachedChangesApplied": false,
    "StopTaskCachedChangesNotApplied": false,
    "MaxFullLoadSubTasks": 8,
    "TransactionConsistencyTimeout": 600,
    "CommitRate": 10000
  },
  "Logging": {
    "EnableLogging": true,
    "LogComponents": [
      {
        "Id": "SOURCE_UNLOAD",
        "Severity": "LOGGER_SEVERITY_DEFAULT"
      },
      {
        "Id": "TARGET_LOAD",
        "Severity": "LOGGER_SEVERITY_DEFAULT"
      },
      {
        "Id": "SOURCE_CAPTURE",
        "Severity": "LOGGER_SEVERITY_DEFAULT"
      },
      {
        "Id": "TARGET_APPLY",
        "Severity": "LOGGER_SEVERITY_DEFAULT"
      }
    ],
    "CloudWatchLogGroup": "dms-tasks-${DMS_REPLICATION_INSTANCE_ID}",
    "CloudWatchLogStream": "dms-task-${MIGRATION_TASK_ID}"
  },
  "ValidationSettings": {
    "EnableValidation": true,
    "ValidationMode": "ROW_LEVEL",
    "ThreadCount": 5,
    "PartitionSize": 10000,
    "FailureMaxCount": 10000,
    "RecordFailureDelayLimitInMinutes": 0,
    "RecordSuspendDelayInMinutes": 30,
    "MaxKeyColumnSize": 8096,
    "TableFailureMaxCount": 1000,
    "ValidationOnly": false,
    "HandleCollationDiff": false,
    "RecordFailureDelayInMinutes": 5,
    "SkipLobColumns": false,
    "ValidationPartialLobSize": 0,
    "ValidationQueryCdcDelaySeconds": 0
  }
}
EOF
    
    success "Configuration files created"
}

# Function to create CloudWatch resources
create_monitoring() {
    log "Creating CloudWatch monitoring resources..."
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name "dms-tasks-${DMS_REPLICATION_INSTANCE_ID}" \
        --retention-in-days 30 || true  # Ignore if already exists
    
    success "CloudWatch monitoring configured"
}

# Function to create migration tasks
create_migration_tasks() {
    log "Creating migration tasks..."
    
    # Get ARNs
    RI_ARN=$(aws dms describe-replication-instances \
        --replication-instance-identifier ${DMS_REPLICATION_INSTANCE_ID} \
        --query 'ReplicationInstances[0].ReplicationInstanceArn' --output text)
    
    SOURCE_ARN=$(aws dms describe-endpoints \
        --endpoint-identifier ${SOURCE_ENDPOINT_ID} \
        --query 'Endpoints[0].EndpointArn' --output text)
    
    TARGET_ARN=$(aws dms describe-endpoints \
        --endpoint-identifier ${TARGET_ENDPOINT_ID} \
        --query 'Endpoints[0].EndpointArn' --output text)
    
    # Create full load and CDC task
    aws dms create-replication-task \
        --replication-task-identifier ${MIGRATION_TASK_ID} \
        --source-endpoint-arn ${SOURCE_ARN} \
        --target-endpoint-arn ${TARGET_ARN} \
        --replication-instance-arn ${RI_ARN} \
        --migration-type full-load-and-cdc \
        --table-mappings file://table-mapping.json \
        --replication-task-settings file://task-settings.json \
        --tags Key=Name,Value=dms-migration-task \
               Key=Environment,Value=migration \
               Key=CreatedBy,Value=dms-migration-recipe
    
    success "Migration task created: ${MIGRATION_TASK_ID}"
    
    # Create CDC-only task
    aws dms create-replication-task \
        --replication-task-identifier ${CDC_TASK_ID} \
        --source-endpoint-arn ${SOURCE_ARN} \
        --target-endpoint-arn ${TARGET_ARN} \
        --replication-instance-arn ${RI_ARN} \
        --migration-type cdc \
        --table-mappings file://table-mapping.json \
        --replication-task-settings file://task-settings.json \
        --tags Key=Name,Value=dms-cdc-task \
               Key=Environment,Value=migration \
               Key=CreatedBy,Value=dms-migration-recipe
    
    success "CDC task created: ${CDC_TASK_ID}"
}

# Function to display deployment summary
show_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
    echo "VPC ID: ${VPC_ID}"
    echo ""
    echo "DMS Resources:"
    echo "- Replication Instance: ${DMS_REPLICATION_INSTANCE_ID}"
    echo "- Subnet Group: ${DMS_SUBNET_GROUP_ID}"
    echo "- Source Endpoint: ${SOURCE_ENDPOINT_ID}"
    echo "- Target Endpoint: ${TARGET_ENDPOINT_ID}"
    echo "- Migration Task: ${MIGRATION_TASK_ID}"
    echo "- CDC Task: ${CDC_TASK_ID}"
    echo ""
    echo "Supporting Resources:"
    echo "- S3 Bucket: ${S3_BUCKET_NAME}"
    echo "- CloudWatch Log Group: dms-tasks-${DMS_REPLICATION_INSTANCE_ID}"
    echo ""
    echo "Next Steps:"
    echo "1. Test endpoint connections in DMS console"
    echo "2. Start migration task when ready:"
    echo "   aws dms start-replication-task --replication-task-arn <task-arn> --start-replication-task-type start-replication"
    echo "3. Monitor progress in DMS console or CloudWatch"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting DMS Database Migration deployment..."
    
    check_prerequisites
    setup_environment
    get_vpc_info
    create_s3_bucket
    create_subnet_group
    create_replication_instance
    create_endpoints
    test_connections
    create_configurations
    create_monitoring
    create_migration_tasks
    
    success "DMS Database Migration infrastructure deployed successfully!"
    show_summary
}

# Run main function
main "$@"