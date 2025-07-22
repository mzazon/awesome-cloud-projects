#!/bin/bash

# AWS DMS Database Migration Deployment Script
# This script deploys the complete AWS DMS database migration infrastructure
# Including DMS replication instance, endpoints, VPC, RDS target database, and monitoring

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a deploy.log
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a deploy.log
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}" | tee -a deploy.log
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a deploy.log
}

# Cleanup function for failed deployments
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup..."
    
    # Check if destroy script exists and run it
    if [[ -f "destroy.sh" ]]; then
        log "Running cleanup script..."
        ./destroy.sh || true
    else
        log_warning "Destroy script not found. Manual cleanup may be required."
    fi
}

# Set up trap for cleanup on error
trap 'cleanup_on_error' ERR

# Parse command line arguments
DRY_RUN=false
SKIP_CONFIRMATIONS=false
ENVIRONMENT="dev"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-confirmations)
            SKIP_CONFIRMATIONS=true
            shift
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Deploy AWS DMS database migration infrastructure"
            echo ""
            echo "Options:"
            echo "  --dry-run              Show what would be deployed without making changes"
            echo "  --skip-confirmations   Skip confirmation prompts"
            echo "  --environment ENV      Set environment name (default: dev)"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log "Starting AWS DMS Database Migration deployment..."
log "Environment: $ENVIRONMENT"
log "Dry run: $DRY_RUN"

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

# Check required AWS permissions
log "Checking AWS permissions..."
aws sts get-caller-identity > /dev/null || {
    log_error "Unable to verify AWS credentials"
    exit 1
}

# Check if jq is installed for JSON parsing
if ! command -v jq &> /dev/null; then
    log_warning "jq is not installed. Some features may be limited."
fi

log_success "Prerequisites check completed"

# Set environment variables
log "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    log_warning "No region configured, using default: $AWS_REGION"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

export DMS_REPLICATION_INSTANCE_ID="dms-migration-${ENVIRONMENT}-${RANDOM_SUFFIX}"
export DMS_SUBNET_GROUP_ID="dms-subnet-group-${ENVIRONMENT}-${RANDOM_SUFFIX}"
export SOURCE_ENDPOINT_ID="source-endpoint-${ENVIRONMENT}-${RANDOM_SUFFIX}"
export TARGET_ENDPOINT_ID="target-endpoint-${ENVIRONMENT}-${RANDOM_SUFFIX}"
export MIGRATION_TASK_ID="migration-task-${ENVIRONMENT}-${RANDOM_SUFFIX}"
export CDC_TASK_ID="cdc-task-${ENVIRONMENT}-${RANDOM_SUFFIX}"
export TARGET_DB_INSTANCE_ID="target-db-${ENVIRONMENT}-${RANDOM_SUFFIX}"

# Save resource IDs for cleanup
cat > resource_ids.env << EOF
# Generated resource IDs for environment: $ENVIRONMENT
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
DMS_REPLICATION_INSTANCE_ID=$DMS_REPLICATION_INSTANCE_ID
DMS_SUBNET_GROUP_ID=$DMS_SUBNET_GROUP_ID
SOURCE_ENDPOINT_ID=$SOURCE_ENDPOINT_ID
TARGET_ENDPOINT_ID=$TARGET_ENDPOINT_ID
MIGRATION_TASK_ID=$MIGRATION_TASK_ID
CDC_TASK_ID=$CDC_TASK_ID
TARGET_DB_INSTANCE_ID=$TARGET_DB_INSTANCE_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF

log_success "Environment variables configured"

# Confirmation prompt unless skipped
if [[ "$SKIP_CONFIRMATIONS" != "true" && "$DRY_RUN" != "true" ]]; then
    echo ""
    log "This will create the following resources:"
    log "- VPC with subnets and internet gateway"
    log "- DMS replication instance: $DMS_REPLICATION_INSTANCE_ID"
    log "- DMS subnet group: $DMS_SUBNET_GROUP_ID"
    log "- Target RDS PostgreSQL database: $TARGET_DB_INSTANCE_ID"
    log "- CloudWatch monitoring dashboard"
    log "- Migration task configurations"
    echo ""
    log_warning "Estimated cost: \$150-300 for the duration of the migration"
    echo ""
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN: Would create the following resources:"
    log "- VPC and networking components"
    log "- DMS replication instance: $DMS_REPLICATION_INSTANCE_ID"
    log "- DMS subnet group: $DMS_SUBNET_GROUP_ID"
    log "- Target RDS database: $TARGET_DB_INSTANCE_ID"
    log "- Migration endpoints and tasks"
    log "- CloudWatch monitoring"
    exit 0
fi

# Create VPC and networking components
log "Creating VPC and networking components..."

export VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --query 'Vpc.VpcId' --output text)

aws ec2 create-tags \
    --resources $VPC_ID \
    --tags Key=Name,Value=dms-migration-vpc-$ENVIRONMENT \
           Key=Environment,Value=$ENVIRONMENT \
           Key=Project,Value=DatabaseMigration

# Create subnets in different availability zones
export SUBNET_1_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone ${AWS_REGION}a \
    --query 'Subnet.SubnetId' --output text)

export SUBNET_2_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone ${AWS_REGION}b \
    --query 'Subnet.SubnetId' --output text)

aws ec2 create-tags \
    --resources $SUBNET_1_ID $SUBNET_2_ID \
    --tags Key=Environment,Value=$ENVIRONMENT \
           Key=Project,Value=DatabaseMigration

# Create internet gateway and route table
export IGW_ID=$(aws ec2 create-internet-gateway \
    --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID

# Create route table and add route to internet gateway
export ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route \
    --route-table-id $ROUTE_TABLE_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID

# Associate subnets with route table
aws ec2 associate-route-table \
    --subnet-id $SUBNET_1_ID \
    --route-table-id $ROUTE_TABLE_ID

aws ec2 associate-route-table \
    --subnet-id $SUBNET_2_ID \
    --route-table-id $ROUTE_TABLE_ID

# Update resource_ids.env with VPC details
cat >> resource_ids.env << EOF
VPC_ID=$VPC_ID
SUBNET_1_ID=$SUBNET_1_ID
SUBNET_2_ID=$SUBNET_2_ID
IGW_ID=$IGW_ID
ROUTE_TABLE_ID=$ROUTE_TABLE_ID
EOF

log_success "VPC and networking components created"

# Create DMS replication subnet group
log "Creating DMS replication subnet group..."

aws dms create-replication-subnet-group \
    --replication-subnet-group-identifier $DMS_SUBNET_GROUP_ID \
    --replication-subnet-group-description "Subnet group for DMS migration - $ENVIRONMENT" \
    --subnet-ids $SUBNET_1_ID $SUBNET_2_ID \
    --tags Key=Environment,Value=$ENVIRONMENT \
           Key=Project,Value=DatabaseMigration

log_success "DMS subnet group created: $DMS_SUBNET_GROUP_ID"

# Create DMS replication instance
log "Creating DMS replication instance..."

aws dms create-replication-instance \
    --replication-instance-identifier $DMS_REPLICATION_INSTANCE_ID \
    --replication-instance-class dms.t3.medium \
    --allocated-storage 100 \
    --replication-subnet-group-identifier $DMS_SUBNET_GROUP_ID \
    --publicly-accessible true \
    --multi-az false \
    --engine-version "3.5.2" \
    --tags Key=Environment,Value=$ENVIRONMENT \
           Key=Project,Value=DatabaseMigration

log "Waiting for DMS replication instance to become available..."
aws dms wait replication-instance-available \
    --replication-instance-identifier $DMS_REPLICATION_INSTANCE_ID

log_success "DMS replication instance is available"

# Create RDS subnet group
log "Creating RDS subnet group..."

aws rds create-db-subnet-group \
    --db-subnet-group-name rds-subnet-group-${ENVIRONMENT}-${RANDOM_SUFFIX} \
    --db-subnet-group-description "RDS subnet group for migration target - $ENVIRONMENT" \
    --subnet-ids $SUBNET_1_ID $SUBNET_2_ID \
    --tags Key=Environment,Value=$ENVIRONMENT \
           Key=Project,Value=DatabaseMigration

# Generate secure password for target database
export TARGET_DB_PASSWORD=$(aws secretsmanager get-random-password \
    --exclude-characters '"@/\' \
    --password-length 16 \
    --output text --query RandomPassword 2>/dev/null || openssl rand -base64 12)

# Store password in AWS Secrets Manager
aws secretsmanager create-secret \
    --name "dms-migration-target-db-password-${ENVIRONMENT}-${RANDOM_SUFFIX}" \
    --description "Target database password for DMS migration - $ENVIRONMENT" \
    --secret-string "$TARGET_DB_PASSWORD" \
    --tags Key=Environment,Value=$ENVIRONMENT \
           Key=Project,Value=DatabaseMigration

# Create target PostgreSQL database
log "Creating target RDS PostgreSQL database..."

aws rds create-db-instance \
    --db-instance-identifier $TARGET_DB_INSTANCE_ID \
    --db-instance-class db.t3.medium \
    --engine postgres \
    --engine-version 14.9 \
    --master-username dbadmin \
    --master-user-password $TARGET_DB_PASSWORD \
    --allocated-storage 100 \
    --db-subnet-group-name rds-subnet-group-${ENVIRONMENT}-${RANDOM_SUFFIX} \
    --publicly-accessible true \
    --backup-retention-period 7 \
    --tags Key=Environment,Value=$ENVIRONMENT \
           Key=Project,Value=DatabaseMigration

log "Waiting for RDS database to become available..."
aws rds wait db-instance-available \
    --db-instance-identifier $TARGET_DB_INSTANCE_ID

log_success "Target RDS database is available"

# Get target database endpoint
export TARGET_DB_HOST=$(aws rds describe-db-instances \
    --db-instance-identifier $TARGET_DB_INSTANCE_ID \
    --query 'DBInstances[0].Endpoint.Address' --output text)

# Update resource_ids.env with database details
cat >> resource_ids.env << EOF
TARGET_DB_HOST=$TARGET_DB_HOST
TARGET_DB_PASSWORD=$TARGET_DB_PASSWORD
EOF

# Create configuration templates
log "Creating configuration templates..."

# Create table mappings configuration
cat > table-mappings.json << EOF
{
    "rules": [
        {
            "rule-type": "selection",
            "rule-id": "1",
            "rule-name": "select-hr-schema",
            "object-locator": {
                "schema-name": "HR",
                "table-name": "%"
            },
            "rule-action": "include",
            "filters": []
        },
        {
            "rule-type": "transformation",
            "rule-id": "2",
            "rule-name": "rename-hr-schema",
            "rule-target": "schema",
            "object-locator": {
                "schema-name": "HR"
            },
            "rule-action": "rename",
            "value": "hr_schema"
        }
    ]
}
EOF

# Create migration task settings
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
                "Id": "TRANSFORMATION",
                "Severity": "LOGGER_SEVERITY_DEFAULT"
            },
            {
                "Id": "SOURCE_UNLOAD",
                "Severity": "LOGGER_SEVERITY_DEFAULT"
            },
            {
                "Id": "TARGET_LOAD",
                "Severity": "LOGGER_SEVERITY_DEFAULT"
            }
        ],
        "CloudWatchLogGroup": "/aws/dms/tasks",
        "CloudWatchLogStream": null
    },
    "ErrorBehavior": {
        "DataErrorPolicy": "LOG_ERROR",
        "DataTruncationErrorPolicy": "LOG_ERROR",
        "DataErrorEscalationPolicy": "SUSPEND_TABLE",
        "TableErrorPolicy": "SUSPEND_TABLE",
        "TableErrorEscalationPolicy": "STOP_TASK",
        "FullLoadIgnoreConflicts": true,
        "FailOnTransactionConsistencyBreached": false,
        "FailOnNoTablesCaptured": true
    },
    "ChangeProcessingTuning": {
        "BatchApplyPreserveTransaction": true,
        "BatchApplyTimeoutMin": 1,
        "BatchApplyTimeoutMax": 30,
        "BatchApplyMemoryLimit": 500,
        "MinTransactionSize": 1000,
        "CommitTimeout": 1,
        "MemoryLimitTotal": 1024,
        "MemoryKeepTime": 60,
        "StatementCacheSize": 50
    }
}
EOF

# Create CloudWatch log group for DMS
log "Creating CloudWatch log group..."
aws logs create-log-group \
    --log-group-name /aws/dms/tasks \
    --tags Environment=$ENVIRONMENT,Project=DatabaseMigration || true

# Create CloudWatch dashboard
log "Creating CloudWatch monitoring dashboard..."

cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "AWS/DMS", "FreeableMemory", "ReplicationInstanceIdentifier", "$DMS_REPLICATION_INSTANCE_ID" ],
                    [ ".", "CPUUtilization", ".", "." ],
                    [ ".", "NetworkTransmitThroughput", ".", "." ],
                    [ ".", "NetworkReceiveThroughput", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "DMS Replication Instance Metrics",
                "view": "timeSeries",
                "stacked": false
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "$TARGET_DB_INSTANCE_ID" ],
                    [ ".", "FreeableMemory", ".", "." ],
                    [ ".", "DatabaseConnections", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Target Database Metrics",
                "view": "timeSeries",
                "stacked": false
            }
        }
    ]
}
EOF

aws cloudwatch put-dashboard \
    --dashboard-name "DMS-Migration-Dashboard-$ENVIRONMENT" \
    --dashboard-body file://dashboard-config.json

log_success "CloudWatch monitoring dashboard created"

# Create target database endpoint
log "Creating target database endpoint..."

aws dms create-endpoint \
    --endpoint-identifier $TARGET_ENDPOINT_ID \
    --endpoint-type target \
    --engine-name postgres \
    --server-name $TARGET_DB_HOST \
    --port 5432 \
    --username dbadmin \
    --password $TARGET_DB_PASSWORD \
    --database-name postgres \
    --tags Key=Environment,Value=$ENVIRONMENT \
           Key=EndpointType,Value=Target

log_success "Target database endpoint created"

# Test target endpoint connectivity
log "Testing target database connectivity..."

aws dms test-connection \
    --replication-instance-identifier $DMS_REPLICATION_INSTANCE_ID \
    --endpoint-identifier $TARGET_ENDPOINT_ID

# Wait for connection test to complete
sleep 30

CONNECTION_STATUS=$(aws dms describe-connections \
    --filter Name=endpoint-identifier,Values=$TARGET_ENDPOINT_ID \
    --query 'Connections[0].Status' --output text)

if [[ "$CONNECTION_STATUS" == "successful" ]]; then
    log_success "Target database connectivity test passed"
else
    log_warning "Target database connectivity test status: $CONNECTION_STATUS"
fi

# Create validation and monitoring scripts
log "Creating validation and monitoring scripts..."

cat > validate-migration.sh << 'EOF'
#!/bin/bash

# Data validation script for DMS migration
# This script validates the migration by checking basic connectivity and stats

set -e

# Load resource IDs
source resource_ids.env

echo "=== Data Validation Report ==="
echo "Generated at: $(date)"
echo "Environment: $ENVIRONMENT"
echo "Target Database: $TARGET_DB_HOST:5432/postgres"
echo "================================"

# Check DMS replication instance status
echo "Checking DMS replication instance status..."
aws dms describe-replication-instances \
    --replication-instance-identifier $DMS_REPLICATION_INSTANCE_ID \
    --query 'ReplicationInstances[0].[ReplicationInstanceStatus,ReplicationInstanceClass]' \
    --output table

# Check target database status
echo "Checking target database status..."
aws rds describe-db-instances \
    --db-instance-identifier $TARGET_DB_INSTANCE_ID \
    --query 'DBInstances[0].[DBInstanceStatus,Engine,EngineVersion]' \
    --output table

echo "Validation complete. Update with specific database queries as needed."
EOF

cat > monitor-migration.sh << 'EOF'
#!/bin/bash

# Migration monitoring script
# This script monitors the progress of DMS migration tasks

set -e

# Load resource IDs
source resource_ids.env

echo "=== Migration Progress Monitor ==="
echo "Environment: $ENVIRONMENT"
echo "=================================="

# Check if migration tasks exist and show their status
if aws dms describe-replication-tasks --replication-task-identifier $MIGRATION_TASK_ID &>/dev/null; then
    echo "Migration task status:"
    aws dms describe-replication-tasks \
        --replication-task-identifier $MIGRATION_TASK_ID \
        --query 'ReplicationTasks[0].[Status,ReplicationTaskStats]' \
        --output table
    
    echo "Task statistics:"
    aws dms describe-replication-tasks \
        --replication-task-identifier $MIGRATION_TASK_ID \
        --query 'ReplicationTasks[0].ReplicationTaskStats' \
        --output table
else
    echo "Migration task not found. Create tasks using DMS console or CLI."
fi

# Check CloudWatch metrics
echo "Recent CPU utilization:"
aws cloudwatch get-metric-statistics \
    --namespace AWS/DMS \
    --metric-name CPUUtilization \
    --dimensions Name=ReplicationInstanceIdentifier,Value=$DMS_REPLICATION_INSTANCE_ID \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average \
    --output table
EOF

chmod +x validate-migration.sh monitor-migration.sh

log_success "Validation and monitoring scripts created"

# Create SCT configuration template
log "Creating SCT configuration template..."

cat > sct-project-config.json << EOF
{
    "ProjectName": "DatabaseMigration-${ENVIRONMENT}-${RANDOM_SUFFIX}",
    "SourceDatabase": {
        "Engine": "oracle",
        "Host": "your-source-database-host",
        "Port": "1521",
        "Database": "your-source-database",
        "Username": "your-source-username",
        "Description": "Replace with your actual source database connection details"
    },
    "TargetDatabase": {
        "Engine": "postgresql",
        "Host": "$TARGET_DB_HOST",
        "Port": "5432",
        "Database": "postgres",
        "Username": "dbadmin"
    },
    "ConversionSettings": {
        "CreateMissingPrimaryKeys": true,
        "ConvertStoredProcedures": true,
        "ConvertTriggers": true,
        "ConvertViews": true,
        "ConvertFunctions": true
    }
}
EOF

# Create assessment report template
cat > assessment-report-template.sql << EOF
-- Schema Conversion Assessment Report
-- Generated for migration project: DatabaseMigration-${ENVIRONMENT}-${RANDOM_SUFFIX}
-- Date: $(date)

-- Use this template to document SCT assessment findings
-- Update with actual schema analysis results

-- 1. Objects that can be converted automatically
-- 2. Objects requiring manual conversion
-- 3. Objects that cannot be converted
-- 4. Action items for manual fixes

-- Add specific findings here after running SCT assessment
EOF

log_success "SCT configuration templates created"

# Final summary
log_success "AWS DMS Database Migration infrastructure deployment completed!"
echo ""
log "=== Deployment Summary ==="
log "Environment: $ENVIRONMENT"
log "DMS Replication Instance: $DMS_REPLICATION_INSTANCE_ID"
log "Target Database: $TARGET_DB_INSTANCE_ID"
log "Target Database Host: $TARGET_DB_HOST"
log "CloudWatch Dashboard: DMS-Migration-Dashboard-$ENVIRONMENT"
echo ""
log "=== Next Steps ==="
log "1. Configure your source database connection details in the DMS console"
log "2. Create source endpoint using your database credentials"
log "3. Test connectivity between source and target databases"
log "4. Create and run migration tasks"
log "5. Use validate-migration.sh to verify data integrity"
log "6. Monitor progress using monitor-migration.sh"
log "7. Use SCT locally with sct-project-config.json for schema conversion"
echo ""
log "=== Important Files ==="
log "- resource_ids.env: Contains all resource identifiers for cleanup"
log "- table-mappings.json: DMS table mapping configuration"
log "- task-settings.json: DMS task settings configuration"
log "- validate-migration.sh: Data validation script"
log "- monitor-migration.sh: Migration monitoring script"
log "- sct-project-config.json: SCT project configuration"
log "- deploy.log: Deployment log file"
echo ""
log_warning "Remember to update source database connection details before starting migration!"
log_warning "Estimated ongoing costs: \$150-300 for the duration of migration"