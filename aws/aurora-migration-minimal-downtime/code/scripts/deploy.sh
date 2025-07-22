#!/bin/bash

# AWS Aurora Minimal Downtime Migration - Deployment Script
# This script creates the infrastructure for migrating on-premises databases to Aurora with minimal downtime

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration file to store deployment variables
CONFIG_FILE="./deployment-config.env"

# Function to save configuration
save_config() {
    cat > "$CONFIG_FILE" << EOF
# Aurora Migration Deployment Configuration
# Generated on $(date)
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export AWS_REGION="$AWS_REGION"
export MIGRATION_SUFFIX="$MIGRATION_SUFFIX"
export DB_INSTANCE_CLASS="$DB_INSTANCE_CLASS"
export REPLICATION_INSTANCE_CLASS="$REPLICATION_INSTANCE_CLASS"
export VPC_ID="$VPC_ID"
export SUBNET_1_ID="$SUBNET_1_ID"
export SUBNET_2_ID="$SUBNET_2_ID"
export AURORA_SG_ID="$AURORA_SG_ID"
export DMS_SG_ID="$DMS_SG_ID"
export AURORA_MASTER_PASSWORD="$AURORA_MASTER_PASSWORD"
export AURORA_CLUSTER_ID="$AURORA_CLUSTER_ID"
export DMS_REPLICATION_INSTANCE_ID="$DMS_REPLICATION_INSTANCE_ID"
export AURORA_ENDPOINT="$AURORA_ENDPOINT"
export AURORA_PORT="$AURORA_PORT"
export SOURCE_ENDPOINT_ID="$SOURCE_ENDPOINT_ID"
export TARGET_ENDPOINT_ID="$TARGET_ENDPOINT_ID"
export MIGRATION_TASK_ID="$MIGRATION_TASK_ID"
export HOSTED_ZONE_ID="$HOSTED_ZONE_ID"
EOF
    log "Configuration saved to $CONFIG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic check)
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity --query Arn --output text | grep -q role; then
        warning "Unable to verify IAM permissions. Ensure you have necessary permissions for RDS, DMS, EC2, and Route53."
    fi
    
    success "Prerequisites check completed"
}

# Function to prompt for source database configuration
configure_source_database() {
    log "Source database configuration required..."
    
    echo "Please provide your source database information:"
    read -p "Source database hostname: " SOURCE_DB_HOSTNAME
    read -p "Source database port (default 3306): " SOURCE_DB_PORT
    SOURCE_DB_PORT=${SOURCE_DB_PORT:-3306}
    read -p "Source database username: " SOURCE_DB_USERNAME
    read -s -p "Source database password: " SOURCE_DB_PASSWORD
    echo
    read -p "Source database name: " SOURCE_DB_NAME
    read -p "Source database engine (mysql/postgresql/oracle/sqlserver): " SOURCE_DB_ENGINE
    SOURCE_DB_ENGINE=${SOURCE_DB_ENGINE:-mysql}
    
    # Export for use in script
    export SOURCE_DB_HOSTNAME SOURCE_DB_PORT SOURCE_DB_USERNAME SOURCE_DB_PASSWORD SOURCE_DB_NAME SOURCE_DB_ENGINE
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region)
    
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export MIGRATION_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    export DB_INSTANCE_CLASS="db.r6g.large"
    export REPLICATION_INSTANCE_CLASS="dms.t3.medium"
    
    success "Environment variables configured"
}

# Function to create VPC infrastructure
create_vpc_infrastructure() {
    log "Creating VPC infrastructure..."
    
    # Create VPC
    export VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
        --tag-specifications \
        'ResourceType=vpc,Tags=[{Key=Name,Value=aurora-migration-vpc}]' \
        --query Vpc.VpcId --output text)
    
    log "Created VPC: $VPC_ID"
    
    # Create subnets
    export SUBNET_1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID \
        --cidr-block 10.0.1.0/24 --availability-zone ${AWS_REGION}a \
        --tag-specifications \
        'ResourceType=subnet,Tags=[{Key=Name,Value=aurora-subnet-1}]' \
        --query Subnet.SubnetId --output text)
    
    export SUBNET_2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID \
        --cidr-block 10.0.2.0/24 --availability-zone ${AWS_REGION}b \
        --tag-specifications \
        'ResourceType=subnet,Tags=[{Key=Name,Value=aurora-subnet-2}]' \
        --query Subnet.SubnetId --output text)
    
    log "Created subnets: $SUBNET_1_ID, $SUBNET_2_ID"
    
    # Create database subnet group
    aws rds create-db-subnet-group \
        --db-subnet-group-name aurora-migration-subnet-group \
        --db-subnet-group-description "Subnet group for Aurora migration" \
        --subnet-ids $SUBNET_1_ID $SUBNET_2_ID \
        --tags Key=Name,Value=aurora-migration-subnet-group
    
    success "VPC infrastructure created"
}

# Function to create security groups
create_security_groups() {
    log "Creating security groups..."
    
    # Aurora security group
    export AURORA_SG_ID=$(aws ec2 create-security-group \
        --group-name aurora-migration-sg \
        --description "Security group for Aurora cluster" \
        --vpc-id $VPC_ID \
        --tag-specifications \
        'ResourceType=security-group,Tags=[{Key=Name,Value=aurora-migration-sg}]' \
        --query GroupId --output text)
    
    # DMS security group
    export DMS_SG_ID=$(aws ec2 create-security-group \
        --group-name dms-replication-sg \
        --description "Security group for DMS replication instance" \
        --vpc-id $VPC_ID \
        --tag-specifications \
        'ResourceType=security-group,Tags=[{Key=Name,Value=dms-replication-sg}]' \
        --query GroupId --output text)
    
    # Configure security group rules
    aws ec2 authorize-security-group-ingress \
        --group-id $AURORA_SG_ID \
        --protocol tcp --port 3306 \
        --source-group $DMS_SG_ID
    
    aws ec2 authorize-security-group-egress \
        --group-id $DMS_SG_ID \
        --protocol tcp --port 3306 \
        --cidr 0.0.0.0/0
    
    success "Security groups created and configured"
}

# Function to generate secure passwords
generate_passwords() {
    log "Generating secure passwords..."
    
    export AURORA_MASTER_PASSWORD=$(aws secretsmanager get-random-password \
        --exclude-punctuation --password-length 16 \
        --require-each-included-type --output text \
        --query RandomPassword 2>/dev/null || openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
    
    success "Passwords generated"
}

# Function to create Aurora cluster
create_aurora_cluster() {
    log "Creating Aurora database cluster..."
    
    # Create parameter group
    aws rds create-db-cluster-parameter-group \
        --db-cluster-parameter-group-name aurora-migration-cluster-pg \
        --db-parameter-group-family aurora-mysql8.0 \
        --description "Parameter group for Aurora migration cluster"
    
    # Optimize parameter group for migration
    aws rds modify-db-cluster-parameter-group \
        --db-cluster-parameter-group-name aurora-migration-cluster-pg \
        --parameters \
        ParameterName=innodb_buffer_pool_size,ParameterValue="{DBInstanceClassMemory*3/4}",ApplyMethod=pending-reboot \
        ParameterName=max_connections,ParameterValue=1000,ApplyMethod=pending-reboot
    
    export AURORA_CLUSTER_ID="aurora-migration-$MIGRATION_SUFFIX"
    
    # Create Aurora cluster
    aws rds create-db-cluster \
        --db-cluster-identifier $AURORA_CLUSTER_ID \
        --engine aurora-mysql \
        --engine-version 8.0.mysql_aurora.3.02.0 \
        --master-username admin \
        --master-user-password $AURORA_MASTER_PASSWORD \
        --database-name migrationdb \
        --vpc-security-group-ids $AURORA_SG_ID \
        --db-subnet-group-name aurora-migration-subnet-group \
        --db-cluster-parameter-group-name aurora-migration-cluster-pg \
        --backup-retention-period 7 \
        --preferred-backup-window "03:00-04:00" \
        --preferred-maintenance-window "sun:04:00-sun:05:00" \
        --enable-cloudwatch-logs-exports error general slowquery \
        --tags Key=Name,Value=$AURORA_CLUSTER_ID \
            Key=Purpose,Value=migration-target
    
    log "Aurora cluster creation initiated: $AURORA_CLUSTER_ID"
    
    # Create database instances
    aws rds create-db-instance \
        --db-instance-identifier ${AURORA_CLUSTER_ID}-primary \
        --db-instance-class $DB_INSTANCE_CLASS \
        --engine aurora-mysql \
        --db-cluster-identifier $AURORA_CLUSTER_ID \
        --publicly-accessible \
        --tags Key=Name,Value=${AURORA_CLUSTER_ID}-primary
    
    aws rds create-db-instance \
        --db-instance-identifier ${AURORA_CLUSTER_ID}-reader \
        --db-instance-class $DB_INSTANCE_CLASS \
        --engine aurora-mysql \
        --db-cluster-identifier $AURORA_CLUSTER_ID \
        --publicly-accessible \
        --tags Key=Name,Value=${AURORA_CLUSTER_ID}-reader
    
    log "Waiting for Aurora cluster to become available..."
    aws rds wait db-cluster-available --db-cluster-identifier $AURORA_CLUSTER_ID
    
    # Get cluster endpoint
    export AURORA_ENDPOINT=$(aws rds describe-db-clusters \
        --db-cluster-identifier $AURORA_CLUSTER_ID \
        --query 'DBClusters[0].Endpoint' --output text)
    export AURORA_PORT=$(aws rds describe-db-clusters \
        --db-cluster-identifier $AURORA_CLUSTER_ID \
        --query 'DBClusters[0].Port' --output text)
    
    success "Aurora cluster created successfully"
    log "Aurora endpoint: $AURORA_ENDPOINT:$AURORA_PORT"
}

# Function to set up DMS infrastructure
setup_dms_infrastructure() {
    log "Setting up DMS infrastructure..."
    
    # Create IAM role for DMS VPC
    cat > dms-vpc-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "dms.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Check if role exists, create if not
    if ! aws iam get-role --role-name dms-vpc-role &>/dev/null; then
        aws iam create-role \
            --role-name dms-vpc-role \
            --assume-role-policy-document file://dms-vpc-trust-policy.json
        
        aws iam attach-role-policy \
            --role-name dms-vpc-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole
        
        log "DMS VPC role created"
        # Wait for role propagation
        sleep 30
    else
        log "DMS VPC role already exists"
    fi
    
    # Create replication subnet group
    aws dms create-replication-subnet-group \
        --replication-subnet-group-identifier dms-migration-subnet-group \
        --replication-subnet-group-description "DMS subnet group for migration" \
        --subnet-ids $SUBNET_1_ID $SUBNET_2_ID \
        --tags Key=Name,Value=dms-migration-subnet-group
    
    export DMS_REPLICATION_INSTANCE_ID="dms-migration-$MIGRATION_SUFFIX"
    
    # Create replication instance
    aws dms create-replication-instance \
        --replication-instance-identifier $DMS_REPLICATION_INSTANCE_ID \
        --replication-instance-class $REPLICATION_INSTANCE_CLASS \
        --allocated-storage 100 \
        --vpc-security-group-ids $DMS_SG_ID \
        --replication-subnet-group-identifier dms-migration-subnet-group \
        --multi-az \
        --publicly-accessible \
        --tags Key=Name,Value=$DMS_REPLICATION_INSTANCE_ID \
            Key=Purpose,Value=database-migration
    
    log "Waiting for DMS replication instance to become available..."
    aws dms wait replication-instance-available \
        --replication-instance-identifier $DMS_REPLICATION_INSTANCE_ID
    
    success "DMS infrastructure created successfully"
}

# Function to create DMS endpoints
create_dms_endpoints() {
    log "Creating DMS endpoints..."
    
    export SOURCE_ENDPOINT_ID="source-$SOURCE_DB_ENGINE-$MIGRATION_SUFFIX"
    export TARGET_ENDPOINT_ID="target-aurora-$MIGRATION_SUFFIX"
    
    # Create source endpoint
    aws dms create-endpoint \
        --endpoint-identifier $SOURCE_ENDPOINT_ID \
        --endpoint-type source \
        --engine-name $SOURCE_DB_ENGINE \
        --server-name "$SOURCE_DB_HOSTNAME" \
        --port $SOURCE_DB_PORT \
        --username "$SOURCE_DB_USERNAME" \
        --password "$SOURCE_DB_PASSWORD" \
        --database-name "$SOURCE_DB_NAME" \
        --extra-connection-attributes "heartbeatEnable=true;heartbeatFrequency=1" \
        --tags Key=Name,Value=$SOURCE_ENDPOINT_ID
    
    # Create target endpoint
    aws dms create-endpoint \
        --endpoint-identifier $TARGET_ENDPOINT_ID \
        --endpoint-type target \
        --engine-name aurora-mysql \
        --server-name $AURORA_ENDPOINT \
        --port $AURORA_PORT \
        --username admin \
        --password $AURORA_MASTER_PASSWORD \
        --database-name migrationdb \
        --extra-connection-attributes "parallelLoadThreads=8;maxFileSize=512000" \
        --tags Key=Name,Value=$TARGET_ENDPOINT_ID
    
    success "DMS endpoints created"
}

# Function to test endpoint connections
test_endpoints() {
    log "Testing endpoint connections..."
    
    # Get DMS instance ARN
    REPLICATION_INSTANCE_ARN=$(aws dms describe-replication-instances \
        --query "ReplicationInstances[?ReplicationInstanceIdentifier=='$DMS_REPLICATION_INSTANCE_ID'].ReplicationInstanceArn" --output text)
    
    # Get endpoint ARNs
    SOURCE_ENDPOINT_ARN=$(aws dms describe-endpoints \
        --query "Endpoints[?EndpointIdentifier=='$SOURCE_ENDPOINT_ID'].EndpointArn" --output text)
    TARGET_ENDPOINT_ARN=$(aws dms describe-endpoints \
        --query "Endpoints[?EndpointIdentifier=='$TARGET_ENDPOINT_ID'].EndpointArn" --output text)
    
    # Test source connection
    log "Testing source database connection..."
    aws dms test-connection \
        --replication-instance-arn $REPLICATION_INSTANCE_ARN \
        --endpoint-arn $SOURCE_ENDPOINT_ARN
    
    # Test target connection
    log "Testing Aurora target connection..."
    aws dms test-connection \
        --replication-instance-arn $REPLICATION_INSTANCE_ARN \
        --endpoint-arn $TARGET_ENDPOINT_ARN
    
    success "Endpoint connectivity tests initiated"
    warning "Check DMS console to verify connection test results"
}

# Function to create migration task configuration files
create_migration_configs() {
    log "Creating migration task configuration files..."
    
    # Create table mappings
    cat > table-mappings.json << 'EOF'
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
      "rule-action": "include"
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
      "value": "migrationdb"
    }
  ]
}
EOF
    
    # Create task settings
    cat > task-settings.json << 'EOF'
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
    "BatchApplyEnabled": true,
    "TaskRecoveryTableEnabled": false,
    "ParallelApplyThreads": 8,
    "ParallelApplyBufferSize": 1000,
    "ParallelApplyQueuesPerThread": 4
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
      },
      {
        "Id": "TASK_MANAGER",
        "Severity": "LOGGER_SEVERITY_DEFAULT"
      }
    ],
    "CloudWatchLogGroup": null,
    "CloudWatchLogStream": null
  },
  "ValidationSettings": {
    "EnableValidation": true,
    "ValidationMode": "ROW_LEVEL",
    "ThreadCount": 5,
    "PartitionSize": 10000,
    "FailureMaxCount": 10000
  }
}
EOF
    
    success "Migration configuration files created"
}

# Function to create migration task
create_migration_task() {
    log "Creating migration task..."
    
    export MIGRATION_TASK_ID="migration-task-$MIGRATION_SUFFIX"
    
    # Get ARNs
    SOURCE_ENDPOINT_ARN=$(aws dms describe-endpoints \
        --query "Endpoints[?EndpointIdentifier=='$SOURCE_ENDPOINT_ID'].EndpointArn" --output text)
    TARGET_ENDPOINT_ARN=$(aws dms describe-endpoints \
        --query "Endpoints[?EndpointIdentifier=='$TARGET_ENDPOINT_ID'].EndpointArn" --output text)
    REPLICATION_INSTANCE_ARN=$(aws dms describe-replication-instances \
        --query "ReplicationInstances[?ReplicationInstanceIdentifier=='$DMS_REPLICATION_INSTANCE_ID'].ReplicationInstanceArn" --output text)
    
    # Create migration task
    aws dms create-replication-task \
        --replication-task-identifier $MIGRATION_TASK_ID \
        --source-endpoint-arn $SOURCE_ENDPOINT_ARN \
        --target-endpoint-arn $TARGET_ENDPOINT_ARN \
        --replication-instance-arn $REPLICATION_INSTANCE_ARN \
        --migration-type full-load-and-cdc \
        --table-mappings file://table-mappings.json \
        --replication-task-settings file://task-settings.json \
        --tags Key=Name,Value=$MIGRATION_TASK_ID
    
    success "Migration task created: $MIGRATION_TASK_ID"
}

# Function to create Route 53 hosted zone
create_route53_zone() {
    log "Creating Route 53 hosted zone for DNS cutover..."
    
    export HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
        --name db.example.com \
        --caller-reference migration-$(date +%s) \
        --hosted-zone-config \
        Comment="DNS zone for database migration cutover" \
        --query 'HostedZone.Id' --output text)
    
    success "Route 53 hosted zone created: $HOSTED_ZONE_ID"
}

# Function to create DNS cutover configuration
create_dns_configs() {
    log "Creating DNS cutover configuration files..."
    
    # DNS record for Aurora
    cat > dns-record-aurora.json << EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "app-db.db.example.com",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [
          {
            "Value": "$AURORA_ENDPOINT"
          }
        ]
      }
    }
  ]
}
EOF
    
    success "DNS configuration files created"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===========================================" 
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo "AWS Region: $AWS_REGION"
    echo "Migration Suffix: $MIGRATION_SUFFIX"
    echo ""
    echo "Aurora Cluster: $AURORA_CLUSTER_ID"
    echo "Aurora Endpoint: $AURORA_ENDPOINT:$AURORA_PORT"
    echo "Aurora Admin Password: $AURORA_MASTER_PASSWORD"
    echo ""
    echo "DMS Instance: $DMS_REPLICATION_INSTANCE_ID"
    echo "Source Endpoint: $SOURCE_ENDPOINT_ID"
    echo "Target Endpoint: $TARGET_ENDPOINT_ID"
    echo "Migration Task: $MIGRATION_TASK_ID"
    echo ""
    echo "Route 53 Zone: $HOSTED_ZONE_ID"
    echo ""
    echo "VPC ID: $VPC_ID"
    echo "Aurora Security Group: $AURORA_SG_ID"
    echo "DMS Security Group: $DMS_SG_ID"
    echo "==========================================="
    echo ""
    warning "IMPORTANT: Save your Aurora admin password securely!"
    echo "Aurora Admin Password: $AURORA_MASTER_PASSWORD"
    echo ""
    log "Configuration saved to: $CONFIG_FILE"
    echo ""
    echo "Next Steps:"
    echo "1. Verify endpoint connections in DMS console"
    echo "2. Start migration task when ready"
    echo "3. Monitor migration progress"
    echo "4. Perform cutover when CDC lag is minimal"
    echo ""
    echo "To start migration task:"
    echo "aws dms start-replication-task --replication-task-arn \$(aws dms describe-replication-tasks --query \"ReplicationTasks[?ReplicationTaskIdentifier=='$MIGRATION_TASK_ID'].ReplicationTaskArn\" --output text) --start-replication-task-type start-replication"
}

# Main deployment function
main() {
    echo "==============================================="
    echo "AWS Aurora Minimal Downtime Migration Deployment"
    echo "==============================================="
    echo ""
    
    # Check if configuration file exists (resume deployment)
    if [ -f "$CONFIG_FILE" ]; then
        echo "Found existing configuration file: $CONFIG_FILE"
        read -p "Do you want to resume deployment with existing config? (y/N): " RESUME
        if [[ $RESUME =~ ^[Yy]$ ]]; then
            source "$CONFIG_FILE"
            log "Resumed with existing configuration"
        else
            rm -f "$CONFIG_FILE"
        fi
    fi
    
    check_prerequisites
    
    if [ ! -f "$CONFIG_FILE" ]; then
        configure_source_database
        setup_environment
        save_config
    fi
    
    # Execute deployment steps
    create_vpc_infrastructure
    save_config
    
    create_security_groups
    save_config
    
    generate_passwords
    save_config
    
    create_aurora_cluster
    save_config
    
    setup_dms_infrastructure
    save_config
    
    create_dms_endpoints
    save_config
    
    test_endpoints
    
    create_migration_configs
    
    create_migration_task
    save_config
    
    create_route53_zone
    save_config
    
    create_dns_configs
    
    # Clean up temporary files
    rm -f dms-vpc-trust-policy.json
    
    success "Deployment completed successfully!"
    display_summary
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi