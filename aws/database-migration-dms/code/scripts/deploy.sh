#!/bin/bash

# AWS DMS Database Migration Deployment Script
# This script deploys a complete database migration solution using AWS DMS
# with replication instance, endpoints, migration task, and monitoring

set -euo pipefail

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling function
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    # Note: In production, you might want to preserve resources for debugging
    # ./destroy.sh
    exit 1
}

trap cleanup_on_error ERR

# Configuration variables (can be overridden by environment variables)
PROJECT_NAME="${PROJECT_NAME:-dms-migration}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
SOURCE_DB_TYPE="${SOURCE_DB_TYPE:-mysql}"
TARGET_DB_TYPE="${TARGET_DB_TYPE:-mysql}"
REPLICATION_INSTANCE_CLASS="${REPLICATION_INSTANCE_CLASS:-dms.t3.medium}"
ALLOCATED_STORAGE="${ALLOCATED_STORAGE:-100}"
ENABLE_MULTI_AZ="${ENABLE_MULTI_AZ:-true}"
ENABLE_DATA_VALIDATION="${ENABLE_DATA_VALIDATION:-true}"
EMAIL_NOTIFICATION="${EMAIL_NOTIFICATION:-}"

# Source database connection details (must be provided via environment variables)
SOURCE_DB_SERVER="${SOURCE_DB_SERVER:-}"
SOURCE_DB_PORT="${SOURCE_DB_PORT:-3306}"
SOURCE_DB_NAME="${SOURCE_DB_NAME:-}"
SOURCE_DB_USERNAME="${SOURCE_DB_USERNAME:-}"
SOURCE_DB_PASSWORD="${SOURCE_DB_PASSWORD:-}"

# Target database connection details (must be provided via environment variables)
TARGET_DB_SERVER="${TARGET_DB_SERVER:-}"
TARGET_DB_PORT="${TARGET_DB_PORT:-3306}"
TARGET_DB_NAME="${TARGET_DB_NAME:-}"
TARGET_DB_USERNAME="${TARGET_DB_USERNAME:-}"
TARGET_DB_PASSWORD="${TARGET_DB_PASSWORD:-}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required environment variables
    if [[ -z "$SOURCE_DB_SERVER" || -z "$SOURCE_DB_NAME" || -z "$SOURCE_DB_USERNAME" || -z "$SOURCE_DB_PASSWORD" ]]; then
        log_error "Source database connection details are required:"
        log_error "  SOURCE_DB_SERVER, SOURCE_DB_NAME, SOURCE_DB_USERNAME, SOURCE_DB_PASSWORD"
        exit 1
    fi
    
    if [[ -z "$TARGET_DB_SERVER" || -z "$TARGET_DB_NAME" || -z "$TARGET_DB_USERNAME" || -z "$TARGET_DB_PASSWORD" ]]; then
        log_error "Target database connection details are required:"
        log_error "  TARGET_DB_SERVER, TARGET_DB_NAME, TARGET_DB_USERNAME, TARGET_DB_PASSWORD"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not configured, using default: $AWS_REGION"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export DMS_REPLICATION_INSTANCE_ID="${PROJECT_NAME}-replication-${RANDOM_SUFFIX}"
    export DMS_SUBNET_GROUP_ID="${PROJECT_NAME}-subnet-group-${RANDOM_SUFFIX}"
    export DMS_SOURCE_ENDPOINT_ID="${PROJECT_NAME}-source-${RANDOM_SUFFIX}"
    export DMS_TARGET_ENDPOINT_ID="${PROJECT_NAME}-target-${RANDOM_SUFFIX}"
    export DMS_TASK_ID="${PROJECT_NAME}-migration-task-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="${PROJECT_NAME}-migration-alerts-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
    log "DMS Replication Instance ID: $DMS_REPLICATION_INSTANCE_ID"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to create SNS topic for notifications
create_sns_topic() {
    log "Creating SNS topic for notifications..."
    
    if aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" &>/dev/null; then
        log_warning "SNS topic already exists, skipping creation"
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    else
        export SNS_TOPIC_ARN=$(aws sns create-topic \
            --name "$SNS_TOPIC_NAME" \
            --output text --query TopicArn)
        
        # Add email subscription if provided
        if [[ -n "$EMAIL_NOTIFICATION" ]]; then
            aws sns subscribe \
                --topic-arn "$SNS_TOPIC_ARN" \
                --protocol email \
                --notification-endpoint "$EMAIL_NOTIFICATION"
            log "Email subscription added. Please confirm subscription in your email."
        fi
        
        log_success "SNS topic created: $SNS_TOPIC_ARN"
    fi
}

# Function to create DMS subnet group
create_subnet_group() {
    log "Creating DMS subnet group..."
    
    # Check if subnet group already exists
    if aws dms describe-replication-subnet-groups \
        --filters "Name=replication-subnet-group-id,Values=$DMS_SUBNET_GROUP_ID" \
        --query 'ReplicationSubnetGroups[0]' --output text | grep -q "$DMS_SUBNET_GROUP_ID" 2>/dev/null; then
        log_warning "DMS subnet group already exists, skipping creation"
        return 0
    fi
    
    # Get VPC and subnets
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [[ "$VPC_ID" == "None" ]]; then
        log_error "No default VPC found. Please specify VPC_ID environment variable."
        exit 1
    fi
    
    # Get subnet IDs from multiple AZs
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[*].SubnetId' --output text)
    
    if [[ -z "$SUBNET_IDS" ]]; then
        log_error "No subnets found in VPC $VPC_ID"
        exit 1
    fi
    
    # Create DMS subnet group
    aws dms create-replication-subnet-group \
        --replication-subnet-group-identifier "$DMS_SUBNET_GROUP_ID" \
        --replication-subnet-group-description \
        "DMS subnet group for ${PROJECT_NAME} migration" \
        --subnet-ids $SUBNET_IDS \
        --tags Key=Project,Value="$PROJECT_NAME" \
        Key=Environment,Value="$ENVIRONMENT"
    
    log_success "DMS subnet group created: $DMS_SUBNET_GROUP_ID"
}

# Function to create DMS replication instance
create_replication_instance() {
    log "Creating DMS replication instance..."
    
    # Check if replication instance already exists
    if aws dms describe-replication-instances \
        --filters "Name=replication-instance-id,Values=$DMS_REPLICATION_INSTANCE_ID" \
        --query 'ReplicationInstances[0].ReplicationInstanceStatus' --output text 2>/dev/null | grep -q "available\|creating\|modifying" 2>/dev/null; then
        log_warning "DMS replication instance already exists or is being created"
        
        # Wait for it to be available
        log "Waiting for existing replication instance to be available..."
        aws dms wait replication-instance-available \
            --replication-instance-arns \
            "arn:aws:dms:${AWS_REGION}:${AWS_ACCOUNT_ID}:rep:${DMS_REPLICATION_INSTANCE_ID}"
        
        log_success "Existing DMS replication instance is available"
        return 0
    fi
    
    # Create replication instance
    aws dms create-replication-instance \
        --replication-instance-identifier "$DMS_REPLICATION_INSTANCE_ID" \
        --replication-instance-class "$REPLICATION_INSTANCE_CLASS" \
        --allocated-storage "$ALLOCATED_STORAGE" \
        --replication-subnet-group-identifier "$DMS_SUBNET_GROUP_ID" \
        --multi-az="$ENABLE_MULTI_AZ" \
        --publicly-accessible \
        --auto-minor-version-upgrade \
        --tags Key=Project,Value="$PROJECT_NAME" \
        Key=Environment,Value="$ENVIRONMENT" \
        Key=Purpose,Value="DatabaseMigration"
    
    log_success "DMS replication instance creation initiated"
    
    # Wait for replication instance to be available
    log "Waiting for replication instance to be available (this may take 5-10 minutes)..."
    aws dms wait replication-instance-available \
        --replication-instance-arns \
        "arn:aws:dms:${AWS_REGION}:${AWS_ACCOUNT_ID}:rep:${DMS_REPLICATION_INSTANCE_ID}"
    
    log_success "DMS replication instance is available"
}

# Function to create database endpoints
create_endpoints() {
    log "Creating database endpoints..."
    
    # Create source endpoint
    if aws dms describe-endpoints \
        --filters "Name=endpoint-id,Values=$DMS_SOURCE_ENDPOINT_ID" \
        --query 'Endpoints[0]' --output text | grep -q "$DMS_SOURCE_ENDPOINT_ID" 2>/dev/null; then
        log_warning "Source endpoint already exists, skipping creation"
    else
        aws dms create-endpoint \
            --endpoint-identifier "$DMS_SOURCE_ENDPOINT_ID" \
            --endpoint-type source \
            --engine-name "$SOURCE_DB_TYPE" \
            --server-name "$SOURCE_DB_SERVER" \
            --port "$SOURCE_DB_PORT" \
            --database-name "$SOURCE_DB_NAME" \
            --username "$SOURCE_DB_USERNAME" \
            --password "$SOURCE_DB_PASSWORD" \
            --ssl-mode require \
            --tags Key=Project,Value="$PROJECT_NAME" \
            Key=Type,Value=Source \
            Key=Environment,Value="$ENVIRONMENT"
        
        log_success "Source endpoint created: $DMS_SOURCE_ENDPOINT_ID"
    fi
    
    # Create target endpoint
    if aws dms describe-endpoints \
        --filters "Name=endpoint-id,Values=$DMS_TARGET_ENDPOINT_ID" \
        --query 'Endpoints[0]' --output text | grep -q "$DMS_TARGET_ENDPOINT_ID" 2>/dev/null; then
        log_warning "Target endpoint already exists, skipping creation"
    else
        aws dms create-endpoint \
            --endpoint-identifier "$DMS_TARGET_ENDPOINT_ID" \
            --endpoint-type target \
            --engine-name "$TARGET_DB_TYPE" \
            --server-name "$TARGET_DB_SERVER" \
            --port "$TARGET_DB_PORT" \
            --database-name "$TARGET_DB_NAME" \
            --username "$TARGET_DB_USERNAME" \
            --password "$TARGET_DB_PASSWORD" \
            --ssl-mode require \
            --tags Key=Project,Value="$PROJECT_NAME" \
            Key=Type,Value=Target \
            Key=Environment,Value="$ENVIRONMENT"
        
        log_success "Target endpoint created: $DMS_TARGET_ENDPOINT_ID"
    fi
}

# Function to test endpoint connections
test_connections() {
    log "Testing database connections..."
    
    # Get ARNs
    REPLICATION_INSTANCE_ARN=$(aws dms describe-replication-instances \
        --filters "Name=replication-instance-id,Values=$DMS_REPLICATION_INSTANCE_ID" \
        --query 'ReplicationInstances[0].ReplicationInstanceArn' --output text)
    
    SOURCE_ENDPOINT_ARN=$(aws dms describe-endpoints \
        --filters "Name=endpoint-id,Values=$DMS_SOURCE_ENDPOINT_ID" \
        --query 'Endpoints[0].EndpointArn' --output text)
    
    TARGET_ENDPOINT_ARN=$(aws dms describe-endpoints \
        --filters "Name=endpoint-id,Values=$DMS_TARGET_ENDPOINT_ID" \
        --query 'Endpoints[0].EndpointArn' --output text)
    
    # Test source endpoint connection
    aws dms test-connection \
        --replication-instance-arn "$REPLICATION_INSTANCE_ARN" \
        --endpoint-arn "$SOURCE_ENDPOINT_ARN"
    
    # Test target endpoint connection
    aws dms test-connection \
        --replication-instance-arn "$REPLICATION_INSTANCE_ARN" \
        --endpoint-arn "$TARGET_ENDPOINT_ARN"
    
    log "Connection tests initiated, waiting for results..."
    sleep 30
    
    # Check connection status
    SOURCE_STATUS=$(aws dms describe-connections \
        --filters "Name=endpoint-arn,Values=$SOURCE_ENDPOINT_ARN" \
        --query 'Connections[0].Status' --output text)
    
    TARGET_STATUS=$(aws dms describe-connections \
        --filters "Name=endpoint-arn,Values=$TARGET_ENDPOINT_ARN" \
        --query 'Connections[0].Status' --output text)
    
    if [[ "$SOURCE_STATUS" == "successful" && "$TARGET_STATUS" == "successful" ]]; then
        log_success "Database connection tests passed"
    else
        log_error "Connection tests failed. Source: $SOURCE_STATUS, Target: $TARGET_STATUS"
        exit 1
    fi
}

# Function to create table mappings
create_table_mappings() {
    log "Creating table mappings configuration..."
    
    # Create table mappings file
    cat > /tmp/table-mappings.json << 'EOF'
{
    "rules": [
        {
            "rule-type": "selection",
            "rule-id": "1",
            "rule-name": "include-all-tables",
            "object-locator": {
                "schema-name": "%",
                "table-name": "%"
            },
            "rule-action": "include",
            "filters": []
        }
    ]
}
EOF
    
    log_success "Table mappings configuration created"
}

# Function to create migration task
create_migration_task() {
    log "Creating migration task..."
    
    # Check if migration task already exists
    if aws dms describe-replication-tasks \
        --filters "Name=replication-task-id,Values=$DMS_TASK_ID" \
        --query 'ReplicationTasks[0]' --output text | grep -q "$DMS_TASK_ID" 2>/dev/null; then
        log_warning "Migration task already exists, skipping creation"
        return 0
    fi
    
    # Create migration task settings
    TASK_SETTINGS='{
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
            ]
        },
        "ErrorBehavior": {
            "DataErrorPolicy": "LOG_ERROR",
            "DataTruncationErrorPolicy": "LOG_ERROR",
            "DataErrorEscalationPolicy": "SUSPEND_TABLE",
            "DataErrorEscalationCount": 0,
            "TableErrorPolicy": "SUSPEND_TABLE",
            "TableErrorEscalationPolicy": "STOP_TASK",
            "TableErrorEscalationCount": 0,
            "RecoverableErrorCount": -1,
            "RecoverableErrorInterval": 5,
            "RecoverableErrorThrottling": true,
            "RecoverableErrorThrottlingMax": 1800,
            "RecoverableErrorStopRetryAfterThrottlingMax": true,
            "ApplyErrorDeletePolicy": "IGNORE_RECORD",
            "ApplyErrorInsertPolicy": "LOG_ERROR",
            "ApplyErrorUpdatePolicy": "LOG_ERROR",
            "ApplyErrorEscalationPolicy": "LOG_ERROR",
            "ApplyErrorEscalationCount": 0,
            "ApplyErrorFailOnTruncationDdl": false,
            "FullLoadIgnoreConflicts": true,
            "FailOnTransactionConsistencyBreached": false,
            "FailOnNoTablesCaptured": true
        }
    }'
    
    # Add data validation settings if enabled
    if [[ "$ENABLE_DATA_VALIDATION" == "true" ]]; then
        TASK_SETTINGS=$(echo "$TASK_SETTINGS" | jq '. + {
            "ValidationSettings": {
                "EnableValidation": true,
                "ValidationMode": "ROW_LEVEL",
                "ThreadCount": 5,
                "PartitionSize": 10000,
                "FailureMaxCount": 10000,
                "RecordFailureDelayInMinutes": 5,
                "RecordSuspendDelayInMinutes": 30,
                "MaxKeyColumnSize": 8096,
                "TableFailureMaxCount": 1000,
                "ValidationOnly": false,
                "HandleCollationDiff": false,
                "RecordFailureDelayLimitInMinutes": 0,
                "SkipLobColumns": false,
                "ValidationPartialLobSize": 0,
                "ValidationQueryCdcDelaySeconds": 0
            }
        }')
    fi
    
    # Create migration task
    aws dms create-replication-task \
        --replication-task-identifier "$DMS_TASK_ID" \
        --source-endpoint-arn "$SOURCE_ENDPOINT_ARN" \
        --target-endpoint-arn "$TARGET_ENDPOINT_ARN" \
        --replication-instance-arn "$REPLICATION_INSTANCE_ARN" \
        --migration-type full-load-and-cdc \
        --table-mappings file:///tmp/table-mappings.json \
        --replication-task-settings "$TASK_SETTINGS" \
        --tags Key=Project,Value="$PROJECT_NAME" \
        Key=Environment,Value="$ENVIRONMENT" \
        Key=Purpose,Value="DatabaseMigration"
    
    log_success "Migration task created: $DMS_TASK_ID"
}

# Function to create event subscription
create_event_subscription() {
    log "Creating event subscription for monitoring..."
    
    SUBSCRIPTION_NAME="${PROJECT_NAME}-events-${RANDOM_SUFFIX}"
    
    # Check if event subscription already exists
    if aws dms describe-event-subscriptions \
        --filters "Name=subscription-name,Values=$SUBSCRIPTION_NAME" \
        --query 'EventSubscriptionsList[0]' --output text | grep -q "$SUBSCRIPTION_NAME" 2>/dev/null; then
        log_warning "Event subscription already exists, skipping creation"
        return 0
    fi
    
    aws dms create-event-subscription \
        --subscription-name "$SUBSCRIPTION_NAME" \
        --sns-topic-arn "$SNS_TOPIC_ARN" \
        --source-type replication-task \
        --event-categories "failure" "creation" "deletion" "state change" \
        --source-ids "$DMS_TASK_ID" \
        --enabled
    
    log_success "Event subscription created: $SUBSCRIPTION_NAME"
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms..."
    
    # Create alarm for task failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-DMS-Task-Failure-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when DMS task fails" \
        --metric-name "ReplicationTaskStatus" \
        --namespace "AWS/DMS" \
        --statistic Average \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=ReplicationTaskIdentifier,Value="$DMS_TASK_ID"
    
    # Create alarm for high latency
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-DMS-High-Latency-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when DMS replication latency is high" \
        --metric-name "CDCLatencySource" \
        --namespace "AWS/DMS" \
        --statistic Average \
        --period 300 \
        --threshold 300 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=ReplicationTaskIdentifier,Value="$DMS_TASK_ID"
    
    log_success "CloudWatch alarms created"
}

# Function to start migration task
start_migration_task() {
    log "Starting migration task..."
    
    # Get migration task ARN
    MIGRATION_TASK_ARN=$(aws dms describe-replication-tasks \
        --filters "Name=replication-task-id,Values=$DMS_TASK_ID" \
        --query 'ReplicationTasks[0].ReplicationTaskArn' --output text)
    
    # Check current task status
    TASK_STATUS=$(aws dms describe-replication-tasks \
        --filters "Name=replication-task-id,Values=$DMS_TASK_ID" \
        --query 'ReplicationTasks[0].Status' --output text)
    
    if [[ "$TASK_STATUS" == "running" ]]; then
        log_warning "Migration task is already running"
        return 0
    elif [[ "$TASK_STATUS" == "starting" ]]; then
        log_warning "Migration task is already starting"
        return 0
    fi
    
    # Start migration task
    aws dms start-replication-task \
        --replication-task-arn "$MIGRATION_TASK_ARN" \
        --start-replication-task-type start-replication
    
    log_success "Migration task started"
    log "Task ARN: $MIGRATION_TASK_ARN"
    
    # Monitor initial task status
    log "Monitoring initial task status..."
    sleep 30
    
    CURRENT_STATUS=$(aws dms describe-replication-tasks \
        --filters "Name=replication-task-id,Values=$DMS_TASK_ID" \
        --query 'ReplicationTasks[0].Status' --output text)
    
    log "Current task status: $CURRENT_STATUS"
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > "./dms-deployment-info.txt" << EOF
AWS DMS Database Migration Deployment Information
================================================

Deployment Date: $(date)
Project Name: $PROJECT_NAME
Environment: $ENVIRONMENT
AWS Region: $AWS_REGION
AWS Account ID: $AWS_ACCOUNT_ID

Resource Identifiers:
- DMS Replication Instance: $DMS_REPLICATION_INSTANCE_ID
- DMS Subnet Group: $DMS_SUBNET_GROUP_ID
- Source Endpoint: $DMS_SOURCE_ENDPOINT_ID
- Target Endpoint: $DMS_TARGET_ENDPOINT_ID
- Migration Task: $DMS_TASK_ID
- SNS Topic: $SNS_TOPIC_ARN

Monitoring:
- CloudWatch Alarms: ${PROJECT_NAME}-DMS-Task-Failure-${RANDOM_SUFFIX}, ${PROJECT_NAME}-DMS-High-Latency-${RANDOM_SUFFIX}
- Event Subscription: ${PROJECT_NAME}-events-${RANDOM_SUFFIX}

To monitor migration progress:
aws dms describe-replication-tasks --filters "Name=replication-task-id,Values=$DMS_TASK_ID"

To check table statistics:
aws dms describe-table-statistics --replication-task-arn arn:aws:dms:${AWS_REGION}:${AWS_ACCOUNT_ID}:task:$(echo $DMS_TASK_ID | tr '[:upper:]' '[:lower:]')

To cleanup resources:
./destroy.sh
EOF
    
    log_success "Deployment information saved to dms-deployment-info.txt"
}

# Main deployment function
main() {
    log "Starting AWS DMS Database Migration deployment..."
    log "Project: $PROJECT_NAME, Environment: $ENVIRONMENT"
    
    check_prerequisites
    setup_environment
    create_sns_topic
    create_subnet_group
    create_replication_instance
    create_endpoints
    test_connections
    create_table_mappings
    create_migration_task
    create_event_subscription
    create_cloudwatch_alarms
    start_migration_task
    save_deployment_info
    
    # Cleanup temporary files
    rm -f /tmp/table-mappings.json
    
    log_success "AWS DMS Database Migration deployment completed successfully!"
    log ""
    log "Next steps:"
    log "1. Monitor migration progress using AWS DMS console or CLI"
    log "2. Check CloudWatch metrics and alarms"
    log "3. Verify data consistency using DMS validation features"
    log "4. Plan application cutover when migration is complete"
    log ""
    log "Deployment information saved to: dms-deployment-info.txt"
}

# Run main function
main "$@"